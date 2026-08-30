//
//  MenuBarItem+Enumeration.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import os.lock

// The unmeasurable half of MenuBarItem, split out following the pattern the
// coverage exclusions describe: keep the algorithm code in a measured file and
// exclude only the part whose substance cannot run in a unit test.
//
// Everything here enumerates real menu bar item windows through Bridging/CGS
// and resolves their owning processes over XPC. What it returns depends on
// which apps are running, which display is active, and whether the window
// server answers -- none of which a CI machine can arrange.
//
// The unchecked initializers and the MenuBarItemTag/Namespace helpers moved
// here with it rather than being widened to internal: they are reachable only
// from this enumeration path, so they stay private to this file.
//
// MenuBarItem itself -- its capability flags, naming, identity, Equatable and
// Hashable conformances and its internal memberwise init -- is a pure value
// type, stays measured, and is covered by MenuBarItemValueTests.

private nonisolated extension MenuBarItem {
    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    @MainActor
    private init(uncheckedItemWindow itemWindow: WindowInfo, instanceIndex: Int = 0) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow, instanceIndex: instanceIndex)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = itemWindow.ownerPID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.isOnScreen = itemWindow.isOnScreen
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @MainActor
    private init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?, instanceIndex: Int = 0) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow, sourcePID: sourcePID, instanceIndex: instanceIndex)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = sourcePID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.isOnScreen = itemWindow.isOnScreen
    }
}

// MARK: - Own Control Items

@MainActor
extension MenuBarItem {
    /// Builds a menu bar item for one of Thaw's own control item windows
    /// from the window ID Thaw itself holds.
    ///
    /// Every other route to a control item goes through the enumerated item
    /// list and can lose it: the primary lookup needs the window to be
    /// present in that list, tag matching needs an intact namespace, and
    /// title matching needs a resolved `sourcePID`. All three fail together
    /// whenever the item service's PID resolution degrades, and the window
    /// itself drops out of the list when it is parked far offscreen or
    /// filtered off the active space. What is left is frame correlation,
    /// which guesses.
    ///
    /// None of that is necessary. Thaw created these `NSStatusItem`s and
    /// holds their windows, so their IDs are known first-hand. This asks the
    /// window server about one specific window rather than searching a list,
    /// and stamps our own PID so the namespace resolves to Thaw even when
    /// nothing else about the item's identity does.
    ///
    /// Returns `nil` when the window server no longer knows the ID, which is
    /// the honest answer: the status item has been torn down or rebuilt, and
    /// a stale ID must not be dressed up as a live item.
    static func ownControlItem(windowID: CGWindowID) -> MenuBarItem? {
        guard let window = WindowInfo(windowID: windowID) else {
            return nil
        }
        return MenuBarItem(
            uncheckedItemWindow: window,
            sourcePID: ProcessInfo.processInfo.processIdentifier
        )
    }
}

// MARK: - MenuBarItem List

nonisolated extension MenuBarItem {
    /// Options that specify the menu bar items in a list.
    struct ListOption: OptionSet {
        let rawValue: Int

        /// Specifies menu bar items that are currently on screen.
        static let onScreen = ListOption(rawValue: 1 << 0)

        /// Specifies menu bar items on the currently active space.
        static let activeSpace = ListOption(rawValue: 1 << 1)
    }

    /// One enumeration together with the source-PID values that came from
    /// persisted seeds instead of the live Accessibility resolver.
    struct EnumerationSnapshot {
        let items: [MenuBarItem]
        let appliedSourcePIDSeeds: [CGWindowID: SourcePIDSeed]
        let windowsByID: [CGWindowID: WindowInfo]
        let controlCenterGeneration: ProcessGeneration?

        var seededSourcePIDWindowIDs: Set<CGWindowID> {
            Set(appliedSourcePIDSeeds.keys)
        }
    }

    private static let diagLog = DiagLog(category: "MenuBarItem")

    /// Creates and returns a list of menu bar items windows for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     item windows across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar item windows.
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
            let key = "\(items[i].tag.namespace):\(items[i].tag.title)"
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
    ) -> EnumerationSnapshot {
        var items = windows.map { window in
            if let title = window.title, title.hasPrefix("Thaw.ControlItem.") {
                let ccBundleID = "com.apple.controlcenter"
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
        return EnumerationSnapshot(
            items: items,
            appliedSourcePIDSeeds: [:],
            windowsByID: Dictionary(
                windows.map { ($0.windowID, $0) },
                uniquingKeysWith: { first, _ in first }
            ),
            controlCenterGeneration: nil
        )
    }

    @available(macOS 26.0, *)
    @MainActor
    private static func getMenuBarItemsExperimental(
        on display: CGDirectDisplayID?,
        option: ListOption,
        resolveSourcePID: Bool
    ) async -> EnumerationSnapshot {
        let windows = getMenuBarItemWindows(on: display, option: option)
        diagLog.debug("getMenuBarItems: processing \(windows.count) windows for source PID resolution")

        guard resolveSourcePID else {
            return makeItemsWithoutResolvingSourcePID(from: windows)
        }

        // Single batch XPC call — resolves all PIDs in one request,
        // avoiding concurrent thread explosion in the XPC service.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ccBundleID = "com.apple.controlcenter"

        let controlItemIndices = Set(windows.indices.filter { i in
            guard let title = windows[i].title, title.hasPrefix("Thaw.ControlItem.") else {
                return false
            }
            return windows[i].owningApplication?.bundleIdentifier == ccBundleID ||
                windows[i].ownerPID == ownPID
        })

        // Control item windows have a locally-known PID. Their AX children are
        // disabled divider elements, so asking the XPC service to resolve them
        // guarantees an unresolved cache miss and can initiate an expensive
        // scan of every running app's extras menu bar.
        let indicesToResolve = windows.indices.filter { !controlItemIndices.contains($0) }
        let resolvedPIDs: [pid_t?] = if indicesToResolve.isEmpty {
            []
        } else {
            await MenuBarItemService.Connection.shared.sourcePIDs(
                for: indicesToResolve.map { windows[$0] }
            )
        }

        var pids = [pid_t?](repeating: nil, count: windows.count)
        if resolvedPIDs.count == indicesToResolve.count {
            for (resolvedIndex, windowIndex) in indicesToResolve.enumerated() {
                pids[windowIndex] = resolvedPIDs[resolvedIndex]
            }
        } else if !indicesToResolve.isEmpty {
            diagLog.error(
                "getMenuBarItems: sourcePIDs returned \(resolvedPIDs.count) entries for \(indicesToResolve.count) windows; treating all as unresolved"
            )
        }

        // A status-item window can survive this app relaunching. Preserve its
        // last confirmed owner while the Accessibility resolver starts cold,
        // but never replace a fresh result from the service.
        let controlCenterGeneration = SourcePIDSeedStore.currentControlCenterGeneration()
        let appliedSeeds: [CGWindowID: SourcePIDSeed] = if let controlCenterGeneration {
            SourcePIDSeedStore.apply(
                seeds: SourcePIDSeedStore.load(from: Defaults.store),
                to: &pids,
                windows: windows,
                currentControlCenterGeneration: controlCenterGeneration,
                liveIdentity: SourcePIDSeedStore.liveIdentity(of:)
            )
        } else {
            [:]
        }
        let seededWindowIDs = Set(appliedSeeds.keys)
        if !appliedSeeds.isEmpty {
            diagLog.info(
                "getMenuBarItems: restored source PIDs for \(appliedSeeds.count) surviving window(s): \(seededWindowIDs.sorted())"
            )
        }

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
            for item in items where item.sourcePID != nil && !seededWindowIDs.contains(item.windowID) {
                if let pid = item.sourcePID {
                    resolvedCountByPID[pid, default: 0] += 1
                }
            }

            // Build a lookup from window title to resolved sourcePID.
            // .resolved(pid) means exactly one PID maps to this title;
            // .ambiguous means multiple different PIDs share the title
            // (e.g. two apps both using "Item-0") and propagation is unsafe.
            var titleToPID = [String: ResolvedPID]()
            for item in items where item.sourcePID != nil && !seededWindowIDs.contains(item.windowID) {
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
        return EnumerationSnapshot(
            items: items,
            appliedSourcePIDSeeds: appliedSeeds,
            windowsByID: Dictionary(
                windows.map { ($0.windowID, $0) },
                uniquingKeysWith: { first, _ in first }
            ),
            controlCenterGeneration: controlCenterGeneration
        )
    }

    /// Creates a menu-bar enumeration while preserving whether each restored
    /// source PID was confirmed live or supplied by the persisted seed store.
    @MainActor
    static func getMenuBarItemsSnapshot(
        on display: CGDirectDisplayID? = nil,
        option: ListOption,
        resolveSourcePID: Bool = true
    ) async -> EnumerationSnapshot {
        diagLog.debug(
            "getMenuBarItems: starting (resolveSourcePID=\(resolveSourcePID))"
        )
        let snapshot = await getMenuBarItemsExperimental(
            on: display,
            option: option,
            resolveSourcePID: resolveSourcePID
        )
        diagLog.debug("getMenuBarItems: returned \(snapshot.items.count) items")
        return snapshot
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
        let snapshot = await getMenuBarItemsSnapshot(
            on: display,
            option: option,
            resolveSourcePID: resolveSourcePID
        )
        return snapshot.items
    }
}

// MARK: - MenuBarItemTag Helper

private nonisolated extension MenuBarItemTag {
    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    @MainActor
    init(uncheckedItemWindow itemWindow: WindowInfo, instanceIndex: Int = 0) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow)
        self.title = itemWindow.title ?? ""
        self.windowID = itemWindow.windowID
        self.instanceIndex = instanceIndex
    }

    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @MainActor
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?, instanceIndex: Int = 0) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
        self.title = itemWindow.title ?? ""
        self.windowID = itemWindow.windowID
        self.instanceIndex = instanceIndex
    }
}

// MARK: - MenuBarItemTag.Namespace Helper

nonisolated extension MenuBarItemTag.Namespace {
    private static let uuidCache = OSAllocatedUnfairLock<[CGWindowID: UUID]>(initialState: [:])

    @MainActor
    static func pruneUUIDCache(keeping validWindowIDs: Set<CGWindowID>) {
        uuidCache.withLock { $0 = $0.filter { validWindowIDs.contains($0.key) } }
    }

    /// The canonicalized bundle identifier for the app, recovering a
    /// transiently nil `bundleIdentifier` through the bundle URL.
    ///
    /// `bundleIdentifier` can read nil for an app that has one (login and
    /// launch races), and the name fallbacks below the callers mint
    /// localized display names for system processes: an en-GB machine
    /// wrote `Control Centre:WiFi` that way, persisted it, and the ghost
    /// then shadowed the canonical `com.apple.controlcenter:WiFi` in the
    /// saved order (#949).
    private static func canonicalBundleIdentifier(of app: NSRunningApplication) -> String? {
        let bundleID = app.bundleIdentifier
            ?? app.bundleURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        return bundleID.map(Self.canonicalBundleID)
    }

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    @MainActor
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        if let app = itemWindow.owningApplication {
            self = .optional(
                Self.canonicalBundleIdentifier(of: app) ?? itemWindow.ownerName ?? app.localizedName
            )
        } else {
            self = .optional(itemWindow.ownerName)
        }
    }

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @MainActor
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        // Check for our own control items by title and owner.
        // On macOS 26, these are owned by Control Center.
        if let title = itemWindow.title, title.hasPrefix("Thaw.ControlItem.") {
            let ccBundleID = "com.apple.controlcenter"
            if itemWindow.owningApplication?.bundleIdentifier == ccBundleID ||
                itemWindow.ownerPID == ProcessInfo.processInfo.processIdentifier
            {
                self = .thaw
                return
            }
        }

        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        // Bundle identifiers are canonicalised so an item hosted by a
        // nested helper is named after the app the user installed. See
        // MenuBarItemTag.Namespace.helperBundleIDAliases. Process names
        // are left alone: the alias table is keyed by bundle ID, and a
        // name that reached this point did so because no bundle ID was
        // available to canonicalise.
        if let sourcePID, let app = NSRunningApplication(processIdentifier: sourcePID) {
            self = .optional(Self.canonicalBundleIdentifier(of: app) ?? app.localizedName)
        } else if let app = itemWindow.owningApplication {
            // Fallback: use the owning application's bundle ID or name.
            // This covers cases where the source PID doesn't resolve
            // (e.g. helper processes) but the owner is known.
            self = .optional(
                Self.canonicalBundleIdentifier(of: app) ?? itemWindow.ownerName ?? app.localizedName
            )
        } else if let ownerName = itemWindow.ownerName {
            // Last resort: use the process name as a stable identifier.
            self = .string(ownerName)
        } else if let uuid = Self.uuidCache.withLock({ $0[itemWindow.windowID] }) {
            self = .uuid(uuid)
        } else {
            let uuid = UUID()
            Self.uuidCache.withLock { $0[itemWindow.windowID] = uuid }
            self = .uuid(uuid)
        }
    }
}

/// Maps a window title to a resolved PID for the PID-propagation pass.
private enum ResolvedPID {
    /// Exactly one PID maps to this title; propagation is safe.
    case resolved(pid_t)
    /// Multiple different PIDs share this title; propagation is unsafe.
    case ambiguous
}
