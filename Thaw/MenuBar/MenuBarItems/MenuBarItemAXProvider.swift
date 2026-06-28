//
//  MenuBarItemAXProvider.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Enumerates menu bar items through the Accessibility tree.
///
/// macOS 27 (Golden Gate) retired the WindowServer mechanism Thaw relied on for
/// every prior release: `CGSGetProcessMenuBarWindowList` no longer returns the
/// individual status-item windows (only the menu bar backdrop), and the new
/// `MenuBarAgent` XPC interface that does expose items is gated behind
/// Apple-private entitlements. Reverse-engineering confirmed that the only
/// mechanism still available to a third-party app is Accessibility.
///
/// Fortunately AX exposes the menu bar cleanly, and with *direct* attribution:
/// every app that owns a status item publishes it under its own application
/// element's `AXExtrasMenuBar`, so the owning process is simply whoever
/// published the child. System items (clock, Control Center, Wi-Fi, …) are
/// published by `MenuBarAgent` itself. This removes the need for the macOS 26
/// marker-pair / spatial source-PID resolution entirely.
///
/// This provider is intentionally read-only: it produces ``MenuBarItem`` values
/// so the layout UI, reordering verification, and capture paths can share the
/// same AX-derived identity/order source. Reordering, hiding, and thumbnails are
/// handled by the macOS 27-specific callers because items are no longer
/// independent windows.
@available(macOS 27, *)
enum MenuBarItemAXProvider {
    private static let diagLog = DiagLog(category: "MenuBarItemAXProvider")

    /// The maximum height an extras-bar child may have to be considered a menu
    /// bar status item. Real items match the menu bar height (~24–30 pt); larger
    /// children are incidental (open popovers, panels) and are skipped.
    private static let maxItemHeight: CGFloat = 40

    /// Returns the menu bar items for the given display by walking the
    /// Accessibility tree of every running application.
    ///
    /// - Parameters:
    ///   - display: A display to filter to, or `nil` for all displays.
    ///   - option: List options. `onScreen` / `activeSpace` are accepted for
    ///     signature parity with the CGS path; AX only reports on-screen items,
    ///     so they are effectively always satisfied.
    static func menuBarItems(
        on display: CGDirectDisplayID? = nil,
        option _: MenuBarItem.ListOption
    ) -> [MenuBarItem] {
        guard AXHelpers.isProcessTrusted() else {
            diagLog.warning("menuBarItems: accessibility permission missing; cannot enumerate")
            return []
        }

        let displayBounds = display.map { CGDisplayBounds($0) }
        let ourBundleID = Bundle.main.bundleIdentifier
        var raw: [RawItem] = []

        for runningApp in NSWorkspace.shared.runningApplications {
            let appBundleID = runningApp.bundleIdentifier ?? runningApp.localizedName ?? "(pid \(runningApp.processIdentifier))"

            guard let app = AXHelpers.application(for: runningApp) else {
                continue
            }
            guard let bar = AXHelpers.extrasMenuBar(for: app) else {
                // Log when Thaw itself has no extras bar — this would prevent control
                // item discovery entirely.
                if runningApp.bundleIdentifier == ourBundleID {
                    diagLog.warning("menuBarItems: Thaw (\(appBundleID)) has no AXExtrasMenuBar — control items cannot be discovered")
                }
                continue
            }

            let children = AXHelpers.children(for: bar)
            diagLog.debug("menuBarItems: \(appBundleID) → \(children.count) child(ren) in AXExtrasMenuBar")
            guard !children.isEmpty else {
                continue
            }

            let namespace = namespace(for: runningApp)
            // Per-app fallback index so untitled items get distinct titles
            // ("Item-0", "Item-1", …), mirroring the CGS window titles.
            var fallbackIndex = 0
            var diagnosticChildDescriptions: [String] = []

            for child in children {
                guard let frame = AXHelpers.frame(for: child) else {
                    continue
                }
                // Skip incidental children (open popovers / panels).
                guard frame.height > 0, frame.height <= maxItemHeight else {
                    continue
                }
                // Restrict to the requested display when one is given.
                if let displayBounds {
                    guard frame.midY >= displayBounds.minY,
                          frame.midY <= displayBounds.maxY,
                          frame.midX >= displayBounds.minX,
                          frame.midX <= displayBounds.maxX
                    else {
                        continue
                    }
                }

                // Keep stable identity metadata separate from the live display
                // title. Scan one level deeper because some apps publish these
                // attributes on the status-bar button rather than its container.
                let identifier = AXHelpers.identifier(for: child)?.nonEmpty
                    ?? AXHelpers.children(for: child)
                        .lazy
                        .compactMap { AXHelpers.identifier(for: $0)?.nonEmpty }
                        .first
                let accessibilityDescription = AXHelpers.description(for: child)?.nonEmpty
                    ?? AXHelpers.children(for: child)
                        .lazy
                        .compactMap { AXHelpers.description(for: $0)?.nonEmpty }
                        .first
                let axTitle = AXHelpers.title(for: child)?.nonEmpty
                let fallbackTitle = "Item-\(fallbackIndex)"
                let displayTitle = axTitle ?? accessibilityDescription ?? identifier ?? fallbackTitle
                if axTitle == nil, accessibilityDescription == nil, identifier == nil {
                    fallbackIndex += 1
                }
                let identityTitle = identityTitle(
                    namespace: namespace,
                    identifier: identifier,
                    accessibilityDescription: accessibilityDescription,
                    displayTitle: displayTitle
                )
                if isNativeOverflowChevronPlaceholder(
                    namespace: namespace,
                    identityTitle: identityTitle,
                    displayTitle: displayTitle
                ) {
                    diagLog.debug("menuBarItems: skipping native overflow chevron placeholder title='\(identityTitle)' frame=\(frame)")
                    continue
                }

                // Direct attribution: the owning process is the app that
                // published this child (fall back to the element's own PID).
                let ownerPID = AXHelpers.pid(for: child) ?? runningApp.processIdentifier

                if runningApp.bundleIdentifier == ourBundleID {
                    diagLog.debug("menuBarItems: Thaw item — title='\(identityTitle)' frame=\(frame) ownerPID=\(ownerPID)")
                }

                if Defaults.bool(forKey: .diagnosticAssessmentModeSceneProbes),
                   runningApp.bundleIdentifier == "com.apple.MenuBarAgent"
                {
                    diagnosticChildDescriptions.append(
                        "\(identityTitle) frame=\(NSStringFromRect(frame)) ownerPID=\(ownerPID)"
                    )
                }

                raw.append(
                    RawItem(
                        namespace: namespace,
                        identityTitle: identityTitle,
                        displayTitle: displayTitle,
                        bounds: frame,
                        ownerPID: ownerPID
                    )
                )
            }

            if Defaults.bool(forKey: .diagnosticAssessmentModeSceneProbes),
               runningApp.bundleIdentifier == "com.apple.MenuBarAgent"
            {
                diagLog.info(
                    "menuBarItems: MenuBarAgent children: " +
                    diagnosticChildDescriptions.joined(separator: " | ")
                )
            }
        }

        let items = assemble(raw)
        diagLog.debug("menuBarItems: enumerated \(items.count) items via AX (display=\(display.map { "\($0)" } ?? "all"))")
        return items
    }

    // MARK: Assembly

    /// A pre-tag item collected from the AX walk.
    private struct RawItem {
        let namespace: MenuBarItemTag.Namespace
        let identityTitle: String
        let displayTitle: String
        let bounds: CGRect
        let ownerPID: pid_t
    }

    /// Builds the final `MenuBarItem` list: assigns stable instance indices to
    /// items that share a (namespace, title) key, synthesizes window IDs, and
    /// sorts left-to-right by position.
    private static func assemble(_ raw: [RawItem]) -> [MenuBarItem] {
        // Sort by x so instance indices are positional and stable.
        let sorted = raw.sorted { $0.bounds.minX < $1.bounds.minX }

        var indexByKey: [String: Int] = [:]
        var items: [MenuBarItem] = []
        items.reserveCapacity(sorted.count)

        for entry in sorted {
            let key = "\(entry.namespace):\(entry.identityTitle)"
            let instanceIndex = indexByKey[key, default: 0]
            indexByKey[key] = instanceIndex + 1

            let windowID = syntheticWindowID(namespace: entry.namespace, title: entry.identityTitle, instanceIndex: instanceIndex)
            let tag = MenuBarItemTag(
                namespace: entry.namespace,
                title: entry.identityTitle,
                windowID: windowID,
                instanceIndex: instanceIndex
            )
            items.append(
                MenuBarItem(
                    tag: tag,
                    windowID: windowID,
                    ownerPID: entry.ownerPID,
                    // Attribution is direct under AX: owner == source.
                    sourcePID: entry.ownerPID,
                    bounds: entry.bounds,
                    title: entry.displayTitle,
                    isOnScreen: true
                )
            )
        }
        return items
    }

    // MARK: Helpers

    /// Maps a running application to the namespace used for its items.
    static func namespace(forBundleIdentifier bundleID: String?, localizedName: String? = nil) -> MenuBarItemTag.Namespace {
        guard let bundleID else {
            return .optional(localizedName)
        }
        switch bundleID {
        case "com.apple.MenuBarAgent":
            return .menuBarAgent
        case _ where Constants.isThawOwnedBundleIdentifier(bundleID):
            return .thaw
        default:
            return .string(bundleID)
        }
    }

    /// Chooses the stable tag title independently from the text shown in the
    /// menu bar. iStat Menus updates `AXTitle` as metrics change, which must not
    /// create a new persisted item identity on every refresh.
    static func identityTitle(
        namespace: MenuBarItemTag.Namespace,
        identifier: String?,
        accessibilityDescription: String?,
        displayTitle: String
    ) -> String {
        if let identifier = identifier?.nonEmpty {
            return identifier
        }

        guard namespace == .string("com.bjango.istatmenus.status") else {
            return displayTitle
        }
        if let accessibilityDescription = accessibilityDescription?.nonEmpty {
            return accessibilityDescription
        }

        // Last-resort compatibility for iStat versions that expose only a
        // changing title. Replace numeric samples, then canonicalize data units
        // whose scale changes with the sample (KB/s -> MB/s). Metric labels stay
        // intact, so separate CPU, memory, upload, and download items remain
        // distinguishable without treating a unit transition as a new item.
        return displayTitle
            .replacing(/[-+]?\d+(?:[.,]\d+)?/, with: "#")
            .replacing(/#\s*[KMGTPE]?[Bb]\/s/, with: "# B/s")
            .replacing(/#\s*[KMGTPE]?[Bb]/, with: "# B")
    }

    /// macOS 27 can publish native menu-bar overflow chevrons as AX extras
    /// under MenuBarAgent. They are not real status items, and managing them
    /// makes the layout editor fill with `<` / `<<` placeholders.
    static func isNativeOverflowChevronPlaceholder(
        namespace: MenuBarItemTag.Namespace,
        identityTitle: String,
        displayTitle: String
    ) -> Bool {
        guard namespace == .menuBarAgent else { return false }

        return [identityTitle, displayTitle].contains { title in
            let glyphs = title.filter { !$0.isWhitespace }
            guard !glyphs.isEmpty, glyphs.count <= 4 else { return false }
            return glyphs.allSatisfy { NativeOverflowChevron.glyphs.contains($0) }
        }
    }

    private static func namespace(for app: NSRunningApplication) -> MenuBarItemTag.Namespace {
        namespace(forBundleIdentifier: app.bundleIdentifier, localizedName: app.localizedName)
    }

    /// Produces a deterministic window identifier for an AX item.
    ///
    /// macOS 27 status items are not independent windows, so they have no real
    /// `CGWindowID`. The rest of the pipeline keys on `windowID` for identity and
    /// always falls back to the item's stored `bounds` when a CGS lookup for the
    /// ID returns nothing, so a stable synthetic ID is safe. The value is pushed
    /// into a high range (top bit set) to minimize collisions with real IDs.
    private static func syntheticWindowID(
        namespace: MenuBarItemTag.Namespace,
        title: String,
        instanceIndex: Int
    ) -> CGWindowID {
        let key = "\(namespace):\(title):\(instanceIndex)"
        // FNV-1a (32-bit) — deterministic regardless of process seed.
        var hash: UInt32 = 0x811C_9DC5
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return CGWindowID(0x8000_0000 | (hash & 0x7FFF_FFFF))
    }
}

private extension String {
    /// Returns `self` when it contains non-whitespace characters, otherwise `nil`.
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

@available(macOS 27, *)
private extension MenuBarItemAXProvider {
    enum NativeOverflowChevron {
        static let glyphs = Set("<>‹›«»")
    }
}
