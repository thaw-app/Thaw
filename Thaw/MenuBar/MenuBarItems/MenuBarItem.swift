//
//  MenuBarItem.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import os.lock
import PlatformRuntimeKit

/// A structural representation of a menu bar item. Extracted to
/// `MenuBarModel.MenuBarItem`.
typealias MenuBarItem = MenuBarModel.MenuBarItem

// MARK: - MenuBarItem (app-only additions)

extension MenuBarItem {
    /// A name associated with the item, suited for display.
    nonisolated var displayName: String {
        // Custom name takes precedence over auto-detected name
        if let custom = customName, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }

        return autoDetectedName
    }

    /// Custom name for this item (persisted).
    ///
    /// Keyed by ``uniqueIdentifier`` (`namespace:title:index`) — windowID is
    /// intentionally excluded because it is transient and changes between
    /// app restarts, which would cause persisted custom names to be lost.
    nonisolated var customName: String? {
        get {
            let names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
            return names[uniqueIdentifier]
        }
        set {
            var names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
            if let newValue, !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                names[uniqueIdentifier] = newValue
            } else {
                names.removeValue(forKey: uniqueIdentifier)
            }
            Defaults.set(names, forKey: .menuBarItemCustomNames)
        }
    }
}

// MARK: - MenuBarItem List

extension MenuBarItem {
    /// Options that specify the menu bar items in a list.
    struct ListOption: OptionSet {
        let rawValue: Int

        /// Specifies menu bar items that are currently on screen.
        static let onScreen = ListOption(rawValue: 1 << 0)

        /// Specifies menu bar items on the currently active space.
        static let activeSpace = ListOption(rawValue: 1 << 1)
    }

    /// Creates and returns a list of menu bar items windows for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     item windows across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar item windows.
    private static let diagLog = DiagLog(category: "MenuBarItem")

    static func getMenuBarItemWindows(on display: CGDirectDisplayID? = nil, option: ListOption) -> [WindowInfo] {
        var bridgingOption: Bridging.MenuBarWindowListOption = .itemsOnly

        if option.contains(.onScreen) {
            bridgingOption.insert(.onScreen)
        }
        if option.contains(.activeSpace) {
            bridgingOption.insert(.activeSpace)
        }

        let rawWindowIDs = Bridging.getMenuBarWindowList(option: bridgingOption)
        diagLog.debug("getMenuBarItemWindows: Bridging returned \(rawWindowIDs.count) window IDs (display=\(display.map { "\($0)" } ?? "nil"))")

        let displayBounds = display.map { CGDisplayBounds($0) }

        let windows = WindowInfo.createWindows(from: rawWindowIDs.reversed()).compactMap { window -> WindowInfo? in
            if let displayBounds {
                // Hidden items are pushed far off-screen horizontally, but they maintain
                // their vertical (Y) coordinate. Filter by the display's Y range.
                let midY = window.bounds.midY
                guard midY >= displayBounds.minY, midY <= displayBounds.maxY else {
                    return nil
                }
            }

            return window
        }

        diagLog.debug("getMenuBarItemWindows: returning \(windows.count) windows from \(rawWindowIDs.count) raw IDs")
        return windows
    }

    /// Creates and returns a list of menu bar items for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     items across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar items.
    @MainActor
    private static func assignStableInstanceIndices(
        to items: inout [MenuBarItem],
        using windows: [WindowInfo]
    ) {
        // Final pass: assign instance indices to allow individual identification
        // of items with the same (namespace, title). Sort by windowID within each
        // group so that indices are stable regardless of item position changes
        // (e.g. dragging between sections). This prevents image cache collisions
        // caused by instanceIndex values swapping between cache cycles.
        var groups = [String: [Int]]()
        for i in 0 ..< items.count {
            let key = "\(items[i].tag.namespace):\(items[i].tag.canonicalTitle)"
            groups[key, default: []].append(i)
        }
        for (_, indices) in groups where indices.count > 1 {
            let sorted = indices.sorted { items[$0].windowID < items[$1].windowID }
            for (instanceIndex, itemIndex) in sorted.enumerated() where instanceIndex > 0 {
                if let sourcePID = items[itemIndex].sourcePID {
                    items[itemIndex] = MenuBarItem(
                        uncheckedItemWindow: windows[itemIndex],
                        sourcePID: sourcePID,
                        instanceIndex: instanceIndex
                    )
                } else {
                    items[itemIndex] = MenuBarItem(
                        uncheckedItemWindow: windows[itemIndex],
                        sourcePID: nil,
                        instanceIndex: instanceIndex
                    )
                }
            }
        }
    }

    @available(macOS 26.0, *)
    @MainActor
    private static func makeItemsWithoutResolvingSourcePID(
        from windows: [WindowInfo]
    ) -> [MenuBarItem] {
        var items = windows.map { window in
            if let title = window.title, title.hasPrefix("Thaw.ControlItem.") {
                let ccBundleID = SharedConstants.menuBarHostingBundleID
                if window.owningApplication?.bundleIdentifier == ccBundleID ||
                    window.ownerPID == ProcessInfo.processInfo.processIdentifier
                {
                    return MenuBarItem(
                        uncheckedItemWindow: window,
                        sourcePID: ProcessInfo.processInfo.processIdentifier
                    )
                }
            }

            return MenuBarItem(uncheckedItemWindow: window, sourcePID: nil)
        }

        assignStableInstanceIndices(to: &items, using: windows)
        let nilPIDCount = items.count(where: { $0.sourcePID == nil })
        diagLog.debug(
            "getMenuBarItemsExperimental: created \(items.count) items without sourcePID resolution, \(nilPIDCount) unresolved"
        )
        return items
    }

    @available(macOS 26.0, *)
    @MainActor
    private static func getMenuBarItemsExperimental(
        on display: CGDirectDisplayID?,
        option: ListOption,
        resolveSourcePID: Bool
    ) async -> [MenuBarItem] {
        let windows = getMenuBarItemWindows(on: display, option: option)
        diagLog.debug("getMenuBarItems: processing \(windows.count) windows for source PID resolution")

        guard resolveSourcePID else {
            return makeItemsWithoutResolvingSourcePID(from: windows)
        }

        // Single batch XPC call — resolves all PIDs in one request,
        // avoiding concurrent thread explosion in the XPC service.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ccBundleID = SharedConstants.menuBarHostingBundleID

        let controlItemIndices = Set(windows.indices.filter { i in
            guard let title = windows[i].title, title.hasPrefix("Thaw.ControlItem.") else {
                return false
            }
            return windows[i].owningApplication?.bundleIdentifier == ccBundleID ||
                windows[i].ownerPID == ownPID
        })

        let pids = await MenuBarItemService.Connection.shared.sourcePIDs(for: windows)

        var items = windows.enumerated().map { index, window in
            let pid: pid_t? = controlItemIndices.contains(index) ? ownPID : pids[index]
            return MenuBarItem(uncheckedItemWindow: window, sourcePID: pid)
        }

        // Post-resolution pass: fix up items with nil sourcePID.
        //
        // The SourcePIDCache resolves PIDs by spatially matching CG window
        // bounds to AX extras menu bar children. When an app registers
        // multiple NSStatusItems (e.g. OneDrive for personal and work
        // accounts), the concurrent resolution may fail for one of the
        // windows due to timing skew between CG and AX coordinate updates.
        //
        // Only propagate a resolved PID to unresolved items sharing
        // the same title when it is safe to do so. We require that
        // the resolved PID already accounts for at least 2 items
        // (across any title), proving the app is a multi-item app.
        // Without this guard, a single-item app's PID could be
        // incorrectly assigned to an unresolved item from a
        // *different* app that happens to share the same title
        // (e.g. two apps both using "Item-0").
        let unresolvedIndices = items.indices.filter { items[$0].sourcePID == nil && !items[$0].isControlItem }
        if !unresolvedIndices.isEmpty {
            // Count how many items each PID has been resolved to.
            var resolvedCountByPID = [pid_t: Int]()
            for item in items where item.sourcePID != nil {
                if let pid = item.sourcePID {
                    resolvedCountByPID[pid, default: 0] += 1
                }
            }

            // Build a lookup from window title to resolved sourcePID.
            // .resolved(pid) means exactly one PID maps to this title;
            // .ambiguous means multiple different PIDs share the title
            // (e.g. two apps both using "Item-0") and propagation is unsafe.
            var titleToPID = [String: ResolvedPID]()
            for item in items where item.sourcePID != nil {
                if let title = item.title, let pid = item.sourcePID {
                    if let existing = titleToPID[title] {
                        // Mark as ambiguous if different PIDs share this title.
                        if case let .resolved(existingPID) = existing, existingPID != pid {
                            titleToPID[title] = .ambiguous
                        }
                    } else {
                        titleToPID[title] = .resolved(pid)
                    }
                }
            }

            for idx in unresolvedIndices {
                let item = items[idx]
                if let title = item.title,
                   case let .resolved(siblingPID) = titleToPID[title]
                {
                    // Only propagate if the resolved PID is already known
                    // to own multiple items, confirming it is a multi-item
                    // app where one window simply failed spatial matching.
                    let resolvedCount = resolvedCountByPID[siblingPID, default: 0]
                    guard resolvedCount >= 2 else {
                        diagLog.debug("getMenuBarItems: skipping propagation of sourcePID \(siblingPID) to windowID \(item.windowID) (title=\(title)) — PID has only \(resolvedCount) resolved item(s)")
                        continue
                    }
                    diagLog.debug("getMenuBarItems: propagating sourcePID \(siblingPID) to unresolved windowID \(item.windowID) (title=\(title))")
                    items[idx] = MenuBarItem(uncheckedItemWindow: windows[idx], sourcePID: siblingPID)
                }
            }
        }

        assignStableInstanceIndices(to: &items, using: windows)

        let nilPIDItems = items.filter { $0.sourcePID == nil }
        if !nilPIDItems.isEmpty {
            let itemsDesc = nilPIDItems.prefix(3).map(\.logString).joined(separator: ", ")
            let moreDesc = nilPIDItems.count > 3 ? " and \(nilPIDItems.count - 3) more" : ""
            diagLog.debug("getMenuBarItems: created \(items.count) items, \(nilPIDItems.count) with nil sourcePID: \(itemsDesc)\(moreDesc)")
        } else {
            diagLog.debug("getMenuBarItems: created \(items.count) items, all with resolved sourcePID")
        }
        return items
    }

    /// Creates and returns a list of menu bar items for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     items across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar items.
    @MainActor
    static func getMenuBarItems(
        on display: CGDirectDisplayID? = nil,
        option: ListOption,
        resolveSourcePID: Bool = true
    ) async -> [MenuBarItem] {
        diagLog.debug(
            "getMenuBarItems: starting (resolveSourcePID=\(resolveSourcePID))"
        )

        // macOS 27 removed the WindowServer menu-bar-item window list that the
        // CGS path depends on. Enumerate through the Accessibility tree instead,
        // which still exposes every item with direct source attribution.
        if #available(macOS 27, *) {
            // Enumeration stays in-process: it runs on the move/settle verify
            // loop hundreds of times per session, and routing that hot path
            // through an out-of-process helper made every call a round trip the
            // single helper could not service, so moves never confirmed.

            // The AX walk makes a synchronous round trip to every running app's
            // accessibility server. Run it off the main actor so an unresponsive
            // app can't block `mach_msg` on the main thread and freeze the whole
            // UI (settings tabs included). The work itself is already serialized
            // onto AXHelpers' background queue; this just keeps the *caller* — the
            // main thread — free to suspend instead of blocking.
            let items = await Task.detached(priority: .userInitiated) {
                MenuBarItemAXProvider.menuBarItems(on: display, option: option)
            }.value
            diagLog.debug("getMenuBarItems: returned \(items.count) items (AX path)")
            return items
        }

        let items = await getMenuBarItemsExperimental(
            on: display,
            option: option,
            resolveSourcePID: resolveSourcePID
        )
        diagLog.debug("getMenuBarItems: returned \(items.count) items")
        return items
    }
}

/// Maps a window title to a resolved PID for the PID-propagation pass.
private enum ResolvedPID {
    /// Exactly one PID maps to this title; propagation is safe.
    case resolved(pid_t)
    /// Multiple different PIDs share this title; propagation is unsafe.
    case ambiguous
}
