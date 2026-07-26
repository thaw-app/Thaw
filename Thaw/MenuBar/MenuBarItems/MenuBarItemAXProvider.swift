//
//  MenuBarItemAXProvider.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa
import MenuBarModel
import PlatformRuntimeKit

nonisolated enum NativeOverflowObservation: Equatable, Sendable {
    case unavailable
    case absent
    case present([CGRect])
}

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
nonisolated enum MenuBarItemAXProvider {
    private static let diagLog = DiagLog(category: "MenuBarItemAXProvider")

    /// The maximum height an extras-bar child may have to be considered a menu
    /// bar status item. Real items match the menu bar height (~24–30 pt); larger
    /// children are incidental (open popovers, panels) and are skipped.
    private static let maxItemHeight: CGFloat = 40

    /// Whether an AX-reported item frame belongs to the given display.
    ///
    /// Uses the frame's midpoint rather than its origin so items straddling
    /// a display boundary (e.g. during a reflow) are attributed to whichever
    /// display they mostly occupy.
    static func frame(_ frame: CGRect, isWithin displayBounds: CGRect) -> Bool {
        frame.midY >= displayBounds.minY &&
            frame.midY <= displayBounds.maxY &&
            frame.midX >= displayBounds.minX &&
            frame.midX <= displayBounds.maxX
    }

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
                if let displayBounds, !Self.frame(frame, isWithin: displayBounds) {
                    continue
                }

                // Keep stable identity metadata separate from the live display
                // title. Scan one level deeper because some apps publish these
                // attributes on the status-bar button rather than its container.
                // NOT `.lazy`: lazy `compactMap` is `map(transform).filter { $0
                // != nil }.map { $0! }`, so it evaluates the transform twice for
                // the first match — once to test non-nil, once to force-unwrap.
                // The transform is a live AX query that can return a different
                // value between the two calls (the item may change or vanish,
                // especially with concurrent enumerations), and the `$0!` then
                // traps. Eager runs each query exactly once; child lists are tiny.
                let identifier = AXHelpers.identifier(for: child)?.nonEmpty
                    ?? AXHelpers.children(for: child)
                    .compactMap { AXHelpers.identifier(for: $0)?.nonEmpty }
                    .first
                let accessibilityDescription = AXHelpers.description(for: child)?.nonEmpty
                    ?? AXHelpers.children(for: child)
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

    /// Presses the system Clock without walking every running application's AX
    /// tree. The Clock may expose the press action on either its extras-bar
    /// container or a nested button, so try both representations.
    static func pressSystemClock(on display: CGDirectDisplayID?) -> Bool {
        guard AXHelpers.isProcessTrusted(),
              let runningApp = NSRunningApplication.runningApplications(
                  withBundleIdentifier: "com.apple.MenuBarAgent"
              ).first,
              let app = AXHelpers.application(for: runningApp),
              let bar = AXHelpers.extrasMenuBar(for: app)
        else {
            return false
        }

        let displayBounds = display.map { CGDisplayBounds($0) }
        for child in AXHelpers.children(for: bar) {
            guard let frame = AXHelpers.frame(for: child),
                  displayBounds.map({ $0.contains(frame.center) }) ?? true
            else {
                continue
            }

            let descendants = AXHelpers.children(for: child)
            let identifier = AXHelpers.identifier(for: child)?.nonEmpty
                ?? descendants.compactMap { AXHelpers.identifier(for: $0)?.nonEmpty }.first
            let accessibilityDescription = AXHelpers.description(for: child)?.nonEmpty
                ?? descendants.compactMap { AXHelpers.description(for: $0)?.nonEmpty }.first
            let displayTitle = AXHelpers.title(for: child)?.nonEmpty
                ?? accessibilityDescription
                ?? identifier
                ?? ""
            let stableTitle = identityTitle(
                namespace: .menuBarAgent,
                identifier: identifier,
                accessibilityDescription: accessibilityDescription,
                displayTitle: displayTitle
            )
            guard SystemMenuBarModuleCatalog.assessmentSystemItemID(forTitle: stableTitle) == 2 else {
                continue
            }

            for element in descendants + [child] where AXHelpers.press(element) {
                return true
            }
        }
        return false
    }

    /// Frames occupied by the native overflow controls on a display. They are
    /// excluded from the managed item list, but capture needs their geometry so
    /// stale item bounds cannot crop the chevrons as item thumbnails.
    static func nativeOverflowControlBounds(on display: CGDirectDisplayID) -> [CGRect] {
        guard case let .present(bounds) = nativeOverflowObservation(on: display) else {
            return []
        }
        return bounds
    }

    /// Distinguishes a trustworthy absence from an AX/MenuBarAgent read that
    /// could not be completed. Runtime monitoring must not interpret a missing
    /// permission or transient agent restart as overflow disappearing.
    static func nativeOverflowObservation(on display: CGDirectDisplayID) -> NativeOverflowObservation {
        guard AXHelpers.isProcessTrusted(),
              let runningApp = NSRunningApplication.runningApplications(
                  withBundleIdentifier: "com.apple.MenuBarAgent"
              ).first,
              let app = AXHelpers.application(for: runningApp),
              let bar = AXHelpers.extrasMenuBar(for: app)
        else {
            return .unavailable
        }

        let displayBounds = CGDisplayBounds(display)
        guard let children = AXHelpers.childrenIfAvailable(for: bar) else {
            return .unavailable
        }
        let descendants = children.flatMap { child -> [AXSwift6.UIElement] in
            let childDescendants = AXHelpers.childrenIfAvailable(for: child) ?? []
            return [child] + childDescendants
        }
        var attributeReadFailed = false
        let attributedControls = ([bar] + children).compactMap { element -> AXSwift6.UIElement? in
            guard let supportsOverflowButton = AXHelpers.supportsOverflowButton(element) else {
                attributeReadFailed = true
                return nil
            }
            guard supportsOverflowButton else { return nil }
            guard let button = AXHelpers.overflowButton(for: element) else {
                attributeReadFailed = true
                return nil
            }
            return button
        }
        let labeledControls = descendants.filter { element in
            let identifier = AXHelpers.identifier(for: element)?.nonEmpty
            let accessibilityDescription = AXHelpers.description(for: element)?.nonEmpty
            let displayTitle = AXHelpers.title(for: element)?.nonEmpty
                ?? accessibilityDescription
                ?? identifier
                ?? ""
            let stableTitle = identityTitle(
                namespace: .menuBarAgent,
                identifier: identifier,
                accessibilityDescription: accessibilityDescription,
                displayTitle: displayTitle
            )
            return isNativeOverflowChevronPlaceholder(
                namespace: .menuBarAgent,
                identityTitle: stableTitle,
                displayTitle: displayTitle
            )
        }

        var seenFrames = Set<CGRect>()
        let frames: [CGRect] = (attributedControls + labeledControls).compactMap { control -> CGRect? in
            guard let frame = AXHelpers.frame(for: control),
                  !frame.isNull,
                  !frame.isEmpty,
                  displayBounds.contains(frame.center),
                  seenFrames.insert(frame).inserted
            else {
                return nil
            }
            return frame
        }
        // The tree walk above finds only the notch-era `AXOverflowButton`. The
        // notchless macOS 27 indicator is a composited `AXImage` that is NOT a
        // child of the extras bar (confirmed: the walk returned `absent` while
        // the chevron was on screen and being clicked). Fall back to a strip
        // hit-test when the walk found nothing. The hit-test lives in
        // PlatformRuntimeKit (`RuntimeOverflowChevronProbe`) so any consumer of
        // the runtime kit inherits chevron detection; this whole type is
        // already `@available(macOS 27, *)` and the chevron is 27-exclusive, so
        // that OS gate is the only gate needed.
        var mergedFrames = frames
        if frames.isEmpty {
            for frame in RuntimeOverflowChevronProbe.detectChevrons(in: displayBounds)
            where seenFrames.insert(frame).inserted {
                mergedFrames.append(frame)
            }
        }

        if mergedFrames.isEmpty, attributeReadFailed || !(attributedControls + labeledControls).isEmpty {
            return .unavailable
        }
        return mergedFrames.isEmpty ? .absent : .present(mergedFrames)
    }

    // MARK: Assembly

    /// A pre-tag item collected from the AX walk.
    ///
    /// Internal (not `private`) and plain-data so `assemble` can be
    /// exercised in tests with fixture instances instead of a live AX walk.
    struct RawItem {
        let namespace: MenuBarItemTag.Namespace
        let identityTitle: String
        let displayTitle: String
        let bounds: CGRect
        let ownerPID: pid_t
    }

    /// Builds the final `MenuBarItem` list: assigns stable instance indices to
    /// items that share a (namespace, title) key, synthesizes window IDs, and
    /// sorts left-to-right by position.
    static func assemble(_ raw: [RawItem]) -> [MenuBarItem] {
        // Sort by x so instance indices are positional and stable.
        let sorted = raw.sorted { $0.bounds.minX < $1.bounds.minX }

        // macOS 27 vends third-party status items twice in the AX tree — once
        // from the owning app's own `AXExtrasMenuBar` and again from
        // MenuBarAgent's. The two copies share the same on-screen position but
        // land under different namespaces (`.string(bundleID)` vs
        // `.menuBarAgent`), so without deduping they receive different instance
        // indices → different tags → different synthetic window IDs, and render
        // as two tiles. Drop the MenuBarAgent re-vend whenever a direct-app
        // entry occupies the same position; MenuBarAgent-only items (Clock,
        // Control Center, and Thaw's own control items arrive under their real
        // namespaces) have no direct twin and are preserved.
        let deduped = dropDuplicateMenuBarAgentRevends(sorted)

        var indexByKey: [String: Int] = [:]
        var items: [MenuBarItem] = []
        items.reserveCapacity(deduped.count)

        for entry in deduped {
            if MenuBarItemTag(namespace: entry.namespace, title: entry.identityTitle).isNativeOverflowPlaceholder ||
                MenuBarItemTag(namespace: entry.namespace, title: entry.displayTitle).isNativeOverflowPlaceholder
            {
                diagLog.debug("assemble: skipping native overflow placeholder title='\(entry.identityTitle)' frame=\(entry.bounds)")
                continue
            }

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
        // For non-iStat apps AXIdentifier is stable by convention; return raw.
        guard namespace == .string("com.bjango.istatmenus.status") else {
            return identifier?.nonEmpty ?? displayTitle
        }

        // iStat Menus may put live metric values in AXIdentifier, AXDescription,
        // or AXTitle depending on the version. Normalize whichever attribute is
        // present so the identity stays stable across per-second updates.
        let candidate = identifier?.nonEmpty
            ?? accessibilityDescription?.nonEmpty
            ?? displayTitle
        return MenuBarItemTag.canonicalIStatMetricTitle(candidate)
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
            let normalized = title.filter { !$0.isWhitespace }
            if normalized.caseInsensitiveCompare("AXOverflowButton") == .orderedSame {
                return true
            }
            // macOS 27 notchless: the collapsed-group indicator describes itself
            // as "Double backward chevron" (SF Symbol chevron.backward.2), not a
            // glyph string. Any MenuBarAgent element whose title/description
            // mentions "chevron" is this indicator — no real menu extra is.
            if title.range(of: "chevron", options: .caseInsensitive) != nil {
                return true
            }
            let glyphs = normalized
            guard !glyphs.isEmpty, glyphs.count <= 4 else { return false }
            return glyphs.allSatisfy { NativeOverflowChevron.glyphs.contains($0) }
        }
    }

    private static func namespace(for app: NSRunningApplication) -> MenuBarItemTag.Namespace {
        namespace(forBundleIdentifier: app.bundleIdentifier, localizedName: app.localizedName)
    }

    /// Positional tolerance (points) within which two AX entries are treated as
    /// the same physical status item vended under two owners. Both coordinates
    /// participate so equal horizontal positions on stacked displays remain
    /// distinct.
    static let duplicateRevendPositionTolerance: CGFloat = 1

    /// Removes MenuBarAgent re-vends of items that are also published directly by
    /// their owning app.
    ///
    /// On macOS 27 a third-party status item appears both in its own app's
    /// `AXExtrasMenuBar` and again in MenuBarAgent's. Keyed by namespace, those
    /// become two independent items. This keeps the direct-app copy (accurate
    /// owner/namespace for persistence and section assignment) and drops the
    /// MenuBarAgent copy whenever the two occupy the same on-screen position.
    /// MenuBarAgent-only entries (no direct twin) are preserved unchanged.
    ///
    /// `sorted` must be ordered by `bounds.minX`.
    static func dropDuplicateMenuBarAgentRevends(_ sorted: [RawItem]) -> [RawItem] {
        let directOrigins = sorted
            .filter { $0.namespace != .menuBarAgent }
            .map { CGPoint(x: $0.bounds.minX, y: $0.bounds.minY) }
        guard !directOrigins.isEmpty else { return sorted }

        return sorted.filter { entry in
            guard entry.namespace == .menuBarAgent else { return true }
            let hasDirectTwin = directOrigins.contains {
                abs($0.x - entry.bounds.minX) <= duplicateRevendPositionTolerance &&
                    abs($0.y - entry.bounds.minY) <= duplicateRevendPositionTolerance
            }
            if hasDirectTwin {
                diagLog.debug(
                    "assemble: dropping MenuBarAgent re-vend title='\(entry.identityTitle)' at minX=\(entry.bounds.minX)"
                )
            }
            return !hasDirectTwin
        }
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
    nonisolated var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

@available(macOS 27, *)
private extension MenuBarItemAXProvider {
    nonisolated enum NativeOverflowChevron {
        static let glyphs = Set("<>‹›«»")
    }
}
