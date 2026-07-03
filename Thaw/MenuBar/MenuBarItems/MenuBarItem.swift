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

    /// Layout-editor movability with experimental system-item hiding applied.
    /// When enabled on macOS 27, forced-visible system items may participate
    /// in assignment-backed section edits.
    func isMovable(experimentalSystemItemHiding: Bool) -> Bool {
        isMovable ||
            (
                experimentalSystemItemHiding &&
                    sectionManagementPolicy.isForcedVisible
            )
    }

    /// Physical MenuBarAgent ordering with experimental system-item hiding
    /// applied. Some forced-visible items can be assigned/hidden by the
    /// experimental assertion but are not accepted as live reorder anchors.
    func isPhysicallyOrderable(experimentalSystemItemHiding: Bool) -> Bool {
        if isControlItem, !tag.matchesVisibleControlItem {
            return false
        }
        if isMovable {
            return true
        }

        guard experimentalSystemItemHiding,
              sectionManagementPolicy.isForcedVisible,
              tag.namespace == .menuBarAgent
        else {
            return false
        }

        return true
    }

    /// A Boolean value that indicates whether this item can be hidden.
    var canBeHidden: Bool {
        sectionManagementPolicy.canBeHidden
    }

    /// Hideability with experimental system-item hiding applied.
    func canBeHidden(experimentalSystemItemHiding: Bool) -> Bool {
        sectionManagementPolicy(
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ).canBeHidden
    }

    /// Legacy divider-layout hideability, independent of the current host OS.
    var canBeHiddenInLegacySectionLayout: Bool {
        tag.canBeHiddenInLegacySectionLayout && !isTransientControlCenterItem
    }

    /// The item's section-management policy, including live-item exclusions
    /// that cannot be determined from its tag alone.
    var sectionManagementPolicy: MenuBarItemTag.SectionManagementPolicy {
        isTransientControlCenterItem ? .excluded : tag.sectionManagementPolicy
    }

    /// Section-management policy with experimental system-item hiding applied.
    func sectionManagementPolicy(
        experimentalSystemItemHiding: Bool
    ) -> MenuBarItemTag.SectionManagementPolicy {
        let basePolicy = sectionManagementPolicy
        // Denylisted hiding-unsupported items stay forced-visible even under the
        // experimental toggle: the editor may reorder them, but they can never be
        // assigned to a hidden section. See ``MenuBarItemTag/isHidingUnsupported``.
        guard experimentalSystemItemHiding, basePolicy.isForcedVisible, !tag.isHidingUnsupported else {
            return basePolicy
        }
        return .hideable
    }

    /// A Boolean value that indicates whether this item is owned by an Apple
    /// system process that cannot be reliably concealed or reordered on macOS 27.
    /// See ``MenuBarItemTag/isNonConcealableSystemItem``.
    var isNonConcealableSystemItem: Bool {
        tag.isNonConcealableSystemItem
    }

    /// Whether this item refers to the same status item as `other`, ignoring the
    /// volatile window ID (synthetic on macOS 27) — matched by namespace/title/
    /// instance plus owning process. Use this to re-locate an item in a freshly
    /// enumerated list rather than comparing window IDs.
    func hasSameIdentity(as other: MenuBarItem) -> Bool {
        tag.matchesIgnoringWindowID(other.tag) &&
            (sourcePID ?? ownerPID) == (other.sourcePID ?? other.ownerPID)
    }

    /// A looser match than ``hasSameIdentity(as:)``: same owning app, ignoring a
    /// possibly-changed transient title (e.g. a Control-Center-style `Item-N`).
    func hasSameOwner(as other: MenuBarItem) -> Bool {
        tag.namespace == other.tag.namespace &&
            (sourcePID ?? ownerPID) == (other.sourcePID ?? other.ownerPID)
    }

    /// Whether AX reports this item parked outside the live menu bar band.
    ///
    /// During assertion reflows macOS 27 temporarily parks items at y≈1400+
    /// while the bar reshuffles. Their X still reads as hidden-side, which
    /// false-triggers layout-divergence detection and doomed synthetic reorders
    /// ("moving Proton to hidden also hid iStat").
    ///
    /// Uses an absolute Y threshold first: when the visible control parks with
    /// collateral, a peer-relative check falsely reports everyone as on-band.
    func isParkedOffMenuBarBand(among peers: [MenuBarItem]) -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return true }

        // Live bar items sit in the top ~60pt of the hosting-window space;
        // assertion reflow parks collateral at y≈1400+.
        if bounds.midY > 80 {
            return true
        }

        guard let barMidY = peers.first(where: {
            $0.tag.matchesVisibleControlItem && $0.bounds.midY <= 80
        })?.bounds.midY
            ?? peers.first(where: {
                $0.isControlItem && $0.bounds.width > 8 && $0.bounds.midY <= 80
            })?.bounds.midY
        else { return false }
        // The live bar band is ~30 pt; parked items are 1000+ pt away on Y.
        return abs(bounds.midY - barMidY) > 48
    }

    /// Whether this visible-assigned item is likely collateral from an
    /// assessment-mode reflow (parked off-band, or physically adjacent to a
    /// concealed item that still appears in AX).
    func isRestrictionReflowCollateral(
        among peers: [MenuBarItem],
        concealedIdentifiers: Set<String>
    ) -> Bool {
        if isParkedOffMenuBarBand(among: peers) {
            return true
        }
        guard !concealedIdentifiers.isEmpty else { return false }

        let sorted = peers
            .filter { !$0.isControlItem && $0.bounds.width > 0 }
            .sorted { $0.bounds.midX < $1.bounds.midX }
        guard let index = sorted.firstIndex(where: { $0.windowID == windowID }) else {
            return false
        }

        for (neighborIndex, neighbor) in sorted.enumerated() where concealedIdentifiers.contains(neighbor.uniqueIdentifier) {
            if abs(neighborIndex - index) <= 1 {
                return true
            }
        }
        return false
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
        tag.tagIdentifier
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
        // Check for our own control items by title and owner.
        // On macOS 26 these are owned by Control Center; on macOS 27+ by MenuBarAgent.
        if let title = itemWindow.title, title.hasPrefix("Thaw.ControlItem.") {
            let ccBundleID = SharedConstants.menuBarHostingBundleID
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
