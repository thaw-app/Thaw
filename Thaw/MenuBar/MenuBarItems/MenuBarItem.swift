//
//  MenuBarItem.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import os.lock

/// A structural representation of a menu bar item.
struct MenuBarItem: CustomStringConvertible {
    /// The tag associated with this item.
    let tag: MenuBarItemTag

    /// The item's window identifier.
    let windowID: CGWindowID

    /// The identifier of the process that owns the item.
    let ownerPID: pid_t

    /// The identifier of the process that created the item.
    let sourcePID: pid_t?

    /// The item's bounds, specified in screen coordinates.
    let bounds: CGRect

    /// The item's window title.
    let title: String?

    /// A Boolean value that indicates whether the item is on screen.
    let isOnScreen: Bool

    /// A Boolean value that indicates whether this item can be moved.
    var isMovable: Bool {
        tag.isMovable
    }

    /// A Boolean value that indicates whether this item can be hidden.
    var canBeHidden: Bool {
        tag.canBeHidden && !isTransientControlCenterItem
    }

    /// A Boolean value that indicates whether this item is a transient
    /// Control Center module (e.g. Live Activities) with a generic
    /// `Item-\d+` title. These are treated like screen recording indicators.
    var isTransientControlCenterItem: Bool {
        tag.isControlCenterGenericItem && sourcePID != nil
    }

    /// A Boolean value that indicates whether this item is one of Ice's
    /// control items.
    var isControlItem: Bool {
        tag.isControlItem
    }

    /// A Boolean value that indicates whether this item is a "BentoBox"
    /// item owned by the Control Center.
    var isBentoBox: Bool {
        tag.isBentoBox
    }

    /// A Boolean value that indicates whether this item is a
    /// system-created clone of an actual item, and therefore invalid
    /// for management.
    var isSystemClone: Bool {
        tag.isSystemClone
    }

    /// The application that owns the item.
    ///
    /// - Note: In macOS 26 and later, this property always returns the
    ///   Control Center. To get the actual application that created the
    ///   item, use ``sourceApplication``.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// The application that created the item.
    ///
    /// - Note: Prior to macOS 26, this property and ``owningApplication``
    ///   are functionally equivalent.
    var sourceApplication: NSRunningApplication? {
        guard let sourcePID else {
            return nil
        }
        return NSRunningApplication(processIdentifier: sourcePID)
    }

    /// The auto-detected name for the item (ignores custom name).
    var autoDetectedName: String {
        /// Converts "UpperCamelCase" to "Title Case".
        ///
        /// Ignores cases where a single lowercase letter immediately
        /// precedes an uppercase letter (i.e. "WiFi").
        func toTitleCase(_ s: some StringProtocol) -> String {
            String(s).replacing(/([a-z]{2})([A-Z])/) { $0.output.1 + " " + $0.output.2 }
        }

        guard !isControlItem else {
            return Constants.displayName
        }

        lazy var fallbackName = "Menu Bar Item"

        guard let sourceApplication else {
            return fallbackName
        }

        lazy var sourceName = sourceApplication.localizedName ?? sourceApplication.bundleIdentifier

        guard let title else {
            return sourceName ?? fallbackName
        }

        lazy var bestName = sourceName ?? title

        guard !isBentoBox else {
            if tag == .controlCenter {
                return bestName
            }
            return title
        }

        let displayName = switch tag.namespace {
        case .passwords, .weather, .textInputMenuAgent:
            toTitleCase(bestName.replacing(/Menu.*/, with: ""))
        case .controlCenter:
            if let match = title.prefixMatch(of: /Hearing/) {
                toTitleCase(match.output)
            } else {
                toTitleCase(title)
            }
        case .systemUIServer:
            if let match = title.firstMatch(of: /TimeMachine/) {
                toTitleCase(match.output)
            } else {
                toTitleCase(title)
            }
        default:
            bestName
        }

        if UUID(uuidString: displayName) != nil, let sourceName {
            return "\(sourceName) (\(displayName))"
        }

        return displayName
    }

    /// A name associated with the item, suited for display.
    var displayName: String {
        // Custom name takes precedence over auto-detected name
        if let custom = customName, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }

        return autoDetectedName
    }

    /// A textual representation of the item.
    var description: String {
        "\(displayName) (\(tag))"
    }

    /// A unique identifier for storing custom names.
    ///
    /// Uses `namespace:title:index` only — windowID is intentionally
    /// excluded because it is transient and changes between app restarts,
    /// which would cause persisted custom names to be lost.
    var uniqueIdentifier: String {
        if tag.instanceIndex > 0 {
            return "\(tag.namespace):\(tag.title):\(tag.instanceIndex)"
        }
        return "\(tag.namespace):\(tag.title)"
    }

    /// Custom name for this item (persisted).
    var customName: String? {
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

    /// A string to use for logging purposes.
    var logString: String {
        "<\(tag) (windowID: \(windowID))>"
    }

    /// A verbose string for diagnosing section classification and move
    /// failures.
    var diagnosticLogString: String {
        let ownerBundleID = owningApplication?.bundleIdentifier ?? "nil"
        let sourcePIDString = sourcePID.map { "\($0)" } ?? "nil"
        let sourceBundleID = sourceApplication?.bundleIdentifier ?? "nil"
        let titleString = title.map { "\"\($0)\"" } ?? "nil"
        return """
        \(logString) id=\(uniqueIdentifier) name="\(displayName)" title=\(titleString) \
        ownerPID=\(ownerPID) ownerBundle=\(ownerBundleID) sourcePID=\(sourcePIDString) \
        sourceBundle=\(sourceBundleID) bounds=\(NSStringFromRect(bounds)) onScreen=\(isOnScreen) \
        movable=\(isMovable) canHide=\(canBeHidden)
        """
    }

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

    /// The result of a raw item fetch after foreign control windows have been
    /// filtered. ItemManager retains the discarded IDs for cache-change
    /// bookkeeping, while ordinary callers only need the safe item list.
    struct FetchedMenuBarItems {
        let items: [MenuBarItem]
        let ghostControlItemWindowIDs: Set<CGWindowID>
    }

    /// Fetches menu bar items together with the foreign control-window IDs
    /// removed from the returned item list.
    @MainActor
    static func fetchMenuBarItems(
        on display: CGDirectDisplayID? = nil,
        option: ListOption,
        resolveSourcePID: Bool = true
    ) async -> FetchedMenuBarItems {
        // Refresh before the PID-resolution pass so a recreated divider is
        // still attributed to this process rather than briefly becoming an
        // unresolved Control Center item. This also gives every direct caller
        // the same ghost filtering previously limited to ItemManager paths.
        // Refresh once before resolving source PIDs, then again after the
        // asynchronous window query. A control item can be recreated while
        // the query is suspended; filtering with the pre-await snapshot would
        // discard the new window as a foreign duplicate and keep the stale
        // one instead.
        _ = currentOwnControlItemWindowIDsByTitle()
        diagLog.debug(
            "fetchMenuBarItems: starting (resolveSourcePID=\(resolveSourcePID))"
        )
        let rawItems = await getMenuBarItemsExperimental(
            on: display,
            option: option,
            resolveSourcePID: resolveSourcePID
        )
        let ownWindowIDsByTitle = currentOwnControlItemWindowIDsByTitle()
        let inactiveControlTitles = ownControlItemWindowIDsProvider == nil
            ? []
            : knownControlItemTitles.subtracting(currentEnabledControlItemTitles())
        let ghostIDs = ghostControlItemWindowIDs(
            in: rawItems,
            ownWindowIDsByTitle: ownWindowIDsByTitle,
            knownInactiveControlTitles: inactiveControlTitles
        )
        let items = rawItems.filter { !ghostIDs.contains($0.windowID) }
        if !ghostIDs.isEmpty {
            diagLog.warning(
                "fetchMenuBarItems: dropped \(ghostIDs.count) foreign control-item window(s) from raw fetch"
            )
        }
        diagLog.debug("fetchMenuBarItems: returned \(items.count) items")
        return FetchedMenuBarItems(
            items: items,
            ghostControlItemWindowIDs: ghostIDs
        )
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

    /// Window IDs of the control item windows this process created.
    ///
    /// MenuBarManager provides a synchronous snapshot on every item fetch so
    /// all consumers, including those outside MenuBarItemManager, can reject
    /// a stale instance's control windows before planning moves or relaunches.
    ///
    /// Control Center hosts every Thaw instance's status items, so the
    /// "Thaw.ControlItem." title prefix alone cannot distinguish this
    /// instance's control items from another instance's (or a crashed
    /// instance's leftovers). Attributing our own PID by title would stamp
    /// a ghost window with a false identity that downstream consumers of
    /// `sourcePID` could trust. Empty until the manager first computes the
    /// authoritative IDs — attribution falls back to the title check then.
    @MainActor static var ownControlItemWindowIDs = Set<CGWindowID>()

    /// The authoritative control-window mapping, keyed by the status item's
    /// stable autosave name (which is also its CG window title).
    @MainActor private static var ownControlItemWindowIDsByTitle = [String: CGWindowID]()

    /// Every control-item title Thaw may create. Once MenuBarManager has
    /// installed its provider, a title missing from the provider's live map
    /// represents a disabled control item, so a window bearing that title can
    /// only belong to another (or defunct) Thaw instance.
    private static let knownControlItemTitles = Set(MenuBarItemTag.controlItems.map(\.title))

    /// Installed by MenuBarManager once it owns the control items. Keeping
    /// the provider weak avoids making this low-level item type retain the
    /// app state graph.
    @MainActor private static var ownControlItemWindowIDsProvider: (() -> [String: CGWindowID])?

    /// Reports enabled controls independently of whether AppKit has supplied
    /// a usable NSStatusItem window number yet. A recreated enabled status
    /// item can briefly have no window; it must not be mistaken for a disabled
    /// foreign control window during that registration interval.
    @MainActor private static var enabledControlItemTitlesProvider: (() -> Set<String>)?

    /// Installs the live control-window provider used to refresh the
    /// authoritative mapping before every fetch.
    @MainActor
    static func setOwnControlItemWindowIDsProvider(
        _ provider: @escaping () -> [String: CGWindowID],
        enabledControlItemTitlesProvider: @escaping () -> Set<String>
    ) {
        ownControlItemWindowIDsProvider = provider
        self.enabledControlItemTitlesProvider = enabledControlItemTitlesProvider
        refreshOwnControlItemWindowIDs()
    }

    /// Returns the current authoritative mapping after refreshing it from the
    /// live NSStatusItem windows when the app has finished setting them up.
    @MainActor
    static func currentOwnControlItemWindowIDsByTitle() -> [String: CGWindowID] {
        refreshOwnControlItemWindowIDs()
        return ownControlItemWindowIDsByTitle
    }

    @MainActor
    private static func currentEnabledControlItemTitles() -> Set<String> {
        enabledControlItemTitlesProvider?() ?? []
    }

    @MainActor
    private static func refreshOwnControlItemWindowIDs() {
        guard let ownControlItemWindowIDsProvider else { return }
        let mapping = ownControlItemWindowIDsProvider()
        ownControlItemWindowIDsByTitle = mapping
        ownControlItemWindowIDs = Set(mapping.values)
    }

    /// Identifies duplicate control windows that belong to another Thaw
    /// instance. The authoritative window must be present in this particular
    /// fetch before a duplicate is discarded, preserving the existing safe
    /// fallback for startup, stale window numbers, and display-filtered lists.
    static nonisolated func ghostControlItemWindowIDs(
        in items: [MenuBarItem],
        ownWindowIDsByTitle: [String: CGWindowID],
        knownInactiveControlTitles: Set<String> = []
    ) -> Set<CGWindowID> {
        var ghostIDs = Set<CGWindowID>()
        for (title, ownWindowID) in ownWindowIDsByTitle {
            guard items.contains(where: { $0.windowID == ownWindowID }) else { continue }
            for item in items where item.title == title && item.windowID != ownWindowID {
                ghostIDs.insert(item.windowID)
            }
        }
        for item in items where item.title.map(knownInactiveControlTitles.contains) == true {
            ghostIDs.insert(item.windowID)
        }
        return ghostIDs
    }

    /// Whether a control-item-titled window is verifiably owned by this
    /// process. Control Center hosts every Thaw instance on macOS 26, so its
    /// owner PID or bundle ID alone cannot establish this identity.
    static nonisolated func isOwnControlItemWindow(
        title: String?,
        ownerPID: pid_t,
        sourcePID: pid_t?
    ) -> Bool {
        guard title?.hasPrefix("Thaw.ControlItem.") == true else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return sourcePID == ownPID || ownerPID == ownPID
    }

    /// Whether our own PID may be attributed to a control-item-titled
    /// window: it must be verifiably ours, or the authoritative set must
    /// not be known yet.
    @MainActor
    private static func canAttributeOwnPID(to window: WindowInfo) -> Bool {
        window.ownerPID == ProcessInfo.processInfo.processIdentifier ||
            ownControlItemWindowIDsProvider == nil ||
            ownControlItemWindowIDs.contains(window.windowID)
    }

    @available(macOS 26.0, *)
    @MainActor
    private static func makeItemsWithoutResolvingSourcePID(
        from windows: [WindowInfo]
    ) -> [MenuBarItem] {
        var items = windows.map { window in
            if let title = window.title, title.hasPrefix("Thaw.ControlItem.") {
                let ccBundleID = "com.apple.controlcenter"
                if (
                    window.owningApplication?.bundleIdentifier == ccBundleID ||
                        window.ownerPID == ProcessInfo.processInfo.processIdentifier
                ) && canAttributeOwnPID(to: window)
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
        let ccBundleID = "com.apple.controlcenter"

        let controlItemIndices = Set(windows.indices.filter { i in
            guard let title = windows[i].title, title.hasPrefix("Thaw.ControlItem.") else {
                return false
            }
            return windows[i].owningApplication?.bundleIdentifier == ccBundleID ||
                windows[i].ownerPID == ownPID
        })

        // Known-own control windows are excluded from the XPC request because
        // their PID is already authoritative. When AppKit cannot publish a
        // window number for a Control-Center-hosted divider, though, ask the
        // service to resolve it through the matching disabled AX child. That
        // preserves ownership without adopting a same-titled divider left by
        // another Thaw process.
        let indicesToResolve = windows.indices.filter {
            !controlItemIndices.contains($0) || !canAttributeOwnPID(to: windows[$0])
        }
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

        var items = windows.enumerated().map { index, window in
            // Control-titled windows use the authoritative local PID when it
            // is available. Otherwise the service may have resolved a disabled
            // AX divider to its actual Thaw process; an unrelated ghost remains
            // nil rather than receiving a false identity.
            let pid: pid_t? = if controlItemIndices.contains(index) {
                canAttributeOwnPID(to: window) ? ownPID : pids[index]
            } else {
                pids[index]
            }
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
        await fetchMenuBarItems(
            on: display,
            option: option,
            resolveSourcePID: resolveSourcePID
        ).items
    }
}

// MARK: - MenuBarItem Init

extension MenuBarItem {
    init(tag: MenuBarItemTag, windowID: CGWindowID, ownerPID: pid_t, sourcePID: pid_t?, bounds: CGRect, title: String?, isOnScreen: Bool) {
        self.tag = tag
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.sourcePID = sourcePID
        self.bounds = bounds
        self.title = title
        self.isOnScreen = isOnScreen
    }
}

// MARK: MenuBarItem: Equatable

extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.tag == rhs.tag &&
            lhs.windowID == rhs.windowID &&
            lhs.ownerPID == rhs.ownerPID &&
            lhs.sourcePID == rhs.sourcePID &&
            lhs.bounds == rhs.bounds &&
            lhs.title == rhs.title &&
            lhs.isOnScreen == rhs.isOnScreen
    }
}

// MARK: MenuBarItem: Hashable

extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
        hasher.combine(windowID)
        hasher.combine(ownerPID)
        hasher.combine(sourcePID)
        hasher.combine(bounds.origin.x)
        hasher.combine(bounds.origin.y)
        hasher.combine(bounds.size.width)
        hasher.combine(bounds.size.height)
        hasher.combine(title)
        hasher.combine(isOnScreen)
    }
}

// MARK: - MenuBarItemTag Helper

private extension MenuBarItemTag {
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

extension MenuBarItemTag.Namespace {
    private static let uuidCache = OSAllocatedUnfairLock<[CGWindowID: UUID]>(initialState: [:])

    @MainActor
    static func pruneUUIDCache(keeping validWindowIDs: Set<CGWindowID>) {
        uuidCache.withLock { $0 = $0.filter { validWindowIDs.contains($0.key) } }
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
        //
        // Use the name of the owning process as a fallback. The non-localized
        // name seems less likely to change, so let's prefer it as a (somewhat)
        // stable identifier.
        if let app = itemWindow.owningApplication {
            self = .optional(app.bundleIdentifier ?? itemWindow.ownerName ?? app.localizedName)
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
        // Check for our own control items by title and verified source.
        // On macOS 26, Control Center hosts every Thaw instance's status
        // windows, so its bundle ID alone cannot establish ownership.
        if MenuBarItem.isOwnControlItemWindow(
            title: itemWindow.title,
            ownerPID: itemWindow.ownerPID,
            sourcePID: sourcePID
        ) {
            self = .thaw
            return
        }

        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        if let sourcePID, let app = NSRunningApplication(processIdentifier: sourcePID) {
            self = .optional(app.bundleIdentifier ?? app.localizedName)
        } else if let app = itemWindow.owningApplication {
            // Fallback: use the owning application's bundle ID or name.
            // This covers cases where the source PID doesn't resolve
            // (e.g. helper processes) but the owner is known.
            self = .optional(app.bundleIdentifier ?? itemWindow.ownerName ?? app.localizedName)
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
