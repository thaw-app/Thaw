//
//  MenuBarItemManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import os.lock

/// Simple actor-based semaphore to prevent overlapping operations
actor SimpleSemaphore {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var value: Int
    private var waiters: [Waiter] = [] // FIFO

    init(value: Int) {
        precondition(value >= 0, "SimpleSemaphore requires a non-negative value")
        self.value = value
    }

    /// Waits for, or decrements, the semaphore, throwing on cancellation.
    func wait() async throws {
        if Task.isCancelled {
            throw CancellationError()
        }

        value -= 1
        if value >= 0 {
            return
        }

        let id = UUID()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: { [weak self] in
            Task.detached { await self?.cancelWaiter(withID: id) }
        }
    }

    private func cancelWaiter(withID id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            // The waiter was already consumed by signal() — don't touch the value.
            return
        }
        value += 1
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    /// An error that indicates the semaphore wait timed out.
    struct TimeoutError: Error {}

    /// Waits for, or decrements, the semaphore with a timeout.
    /// Throws ``CancellationError`` on cancellation or
    /// ``TimeoutError`` on timeout.
    func wait(timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.wait()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimeoutError()
            }
            // The first task to finish (or throw) wins.
            _ = try await group.next()
            group.cancelAll()
        }
    }

    /// Signals the semaphore, resuming the next waiter if present.
    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume(returning: ())
        } else {
            value += 1
        }
    }
}

/// Manager for menu bar items.
@MainActor
final class MenuBarItemManager: ObservableObject {
    static let layoutWatchdogTimeout: DispatchTimeInterval = .seconds(6)

    /// Delay between relocation/restore moves and the subsequent recache,
    /// giving macOS time to settle menu bar item positions.
    static let uiSettleDelay: Duration = .milliseconds(300)

    /// The current cache of menu bar items.
    @Published private(set) var itemCache = ItemCache(displayID: nil)

    /// A Boolean value that indicates whether the control items for the
    /// hidden sections are missing from the menu bar.
    @Published private(set) var areControlItemsMissing = false

    /// Diagnostic logger for the menu bar item manager.
    fileprivate static nonisolated let diagLog = DiagLog(category: "MenuBarItemManager")

    /// Semaphore to prevent overlapping event operations.
    private let eventSemaphore = SimpleSemaphore(value: 1)

    /// Actor for managing menu bar item cache operations.
    private let cacheActor = CacheActor()

    /// Contexts for temporarily shown menu bar items.
    private var temporarilyShownItemContexts = [TemporarilyShownItemContext]()

    /// A timer for rehiding temporarily shown menu bar items.
    private var rehideTimer: Timer?
    private var rehideCancellable: AnyCancellable?

    /// Timestamp of the most recent menu bar item move operation.
    private var lastMoveOperationTimestamp: ContinuousClock.Instant?

    /// Cached timeouts for move operations.
    private var moveOperationTimeouts = [MenuBarItemTag: Duration]()
    
    /// Cached timeouts for click operations (adaptive per app).
    private var clickOperationTimeouts = [MenuBarItemTag: Duration]()
    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Timer for lightweight periodic cache checks.
    private var cacheTickCancellable: AnyCancellable?

    /// Persisted identifiers of menu bar items we've already seen.
    private var knownItemIdentifiers = Set<String>()
    /// Suppresses the next automatic relocation of newly seen leftmost items.
    private var suppressNextNewLeftmostItemRelocation = false
    /// Continuation to signal when background cache task completes.
    private var backgroundCacheContinuation: CheckedContinuation<Void, Never>?
    /// Suppresses image cache updates during layout reset to prevent stale cache during moves.
    var isResettingLayout = false
    /// Suppresses saving section order during an active order-restore pass.
    private var isRestoringItemOrder = false
    /// Timestamp when isRestoringItemOrder was set (for timeout detection).
    private var isRestoringItemOrderTimestamp: Date?
    /// Persisted bundle identifiers explicitly placed in hidden section.
    private var pinnedHiddenBundleIDs = Set<String>()
    /// Persisted bundle identifiers explicitly placed in always-hidden section.
    private var pinnedAlwaysHiddenBundleIDs = Set<String>()

    /// Persisted mapping of item tag identifiers to their original section name for
    /// temporarily shown items whose apps quit before they could be rehidden. When
    /// the app relaunches, this allows us to move the item back to its original section.
    private var pendingRelocations = [String: String]()

    /// Persisted mapping of item tag identifiers to their return destination for
    /// temporarily shown items. Stores the neighbor tag and position to restore
    /// the original ordering when the app relaunches.
    private var pendingReturnDestinations = [String: [String: String]]() // [tagIdentifier: ["neighbor": tag, "position": "left"|"right"]]

    /// Persisted per-section item order. Maps section key to an ordered list of
    /// `uniqueIdentifier` strings (right-to-left, matching cache array order).
    private var savedSectionOrder = [String: [String]]()

    /// Loads persisted known item identifiers.
    private func loadKnownItemIdentifiers() {
        let key = "MenuBarItemManager.knownItemIdentifiers"
        let defaults = UserDefaults.standard
        if let stored = defaults.array(forKey: key) as? [String] {
            knownItemIdentifiers = Set(stored)
        }
    }

    /// Persists known item identifiers.
    private func persistKnownItemIdentifiers() {
        let key = "MenuBarItemManager.knownItemIdentifiers"
        let defaults = UserDefaults.standard
        defaults.set(Array(knownItemIdentifiers), forKey: key)
    }

    /// Loads persisted pinned bundle identifiers.
    private func loadPinnedBundleIDs() {
        let defaults = UserDefaults.standard
        if let hidden = defaults.array(forKey: "MenuBarItemManager.pinnedHiddenBundleIDs") as? [String] {
            pinnedHiddenBundleIDs = Set(hidden)
        }
        if let alwaysHidden = defaults.array(forKey: "MenuBarItemManager.pinnedAlwaysHiddenBundleIDs") as? [String] {
            pinnedAlwaysHiddenBundleIDs = Set(alwaysHidden)
        }
    }

    /// Persists pinned bundle identifiers.
    private func persistPinnedBundleIDs() {
        let defaults = UserDefaults.standard
        defaults.set(Array(pinnedHiddenBundleIDs), forKey: "MenuBarItemManager.pinnedHiddenBundleIDs")
        defaults.set(Array(pinnedAlwaysHiddenBundleIDs), forKey: "MenuBarItemManager.pinnedAlwaysHiddenBundleIDs")
    }

    /// Loads persisted pending relocations for temporarily shown items
    /// whose apps quit before they could be rehidden.
    private func loadPendingRelocations() {
        let key = "MenuBarItemManager.pendingRelocations"
        if let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String] {
            pendingRelocations = stored
        }
        let destKey = "MenuBarItemManager.pendingReturnDestinations"
        if let stored = UserDefaults.standard.dictionary(forKey: destKey) as? [String: [String: String]] {
            pendingReturnDestinations = stored
        }
    }

    /// Persists pending relocations.
    private func persistPendingRelocations() {
        let key = "MenuBarItemManager.pendingRelocations"
        UserDefaults.standard.set(pendingRelocations, forKey: key)
        let destKey = "MenuBarItemManager.pendingReturnDestinations"
        UserDefaults.standard.set(pendingReturnDestinations, forKey: destKey)
    }

    /// Loads persisted section order.
    private func loadSavedSectionOrder() {
        let key = "MenuBarItemManager.savedSectionOrder"
        if let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] {
            savedSectionOrder = stored
        }
    }

    /// Persists the current saved section order.
    private func persistSavedSectionOrder() {
        let key = "MenuBarItemManager.savedSectionOrder"
        UserDefaults.standard.set(savedSectionOrder, forKey: key)
    }

    /// Extracts the current per-section item order from the given cache and
    /// persists it. Skips the write when the order has not changed.
    /// For items currently in the cache, uses their current section.
    /// For items from apps that are closed (not in cache), preserves their saved section.
    private func saveSectionOrder(from cache: ItemCache) {
        var newOrder = [String: [String]]()

        // Build a set of all identifiers currently in the cache
        var allCurrentIdentifiers = Set<String>()
        for section in MenuBarSection.Name.allCases {
            let identifiers = cache[section]
                .filter { !$0.isControlItem }
                .map(\.uniqueIdentifier)
            allCurrentIdentifiers.formUnion(identifiers)
        }

        for section in MenuBarSection.Name.allCases {
            // Start with current identifiers for this section (they belong here now)
            var identifiers = cache[section]
                .filter { !$0.isControlItem }
                .map(\.uniqueIdentifier)

            // Add identifiers from saved sections that are NOT currently in the cache
            // (i.e., apps that are closed - preserve their saved section)
            for (sectionKeyString, savedIdentifiers) in savedSectionOrder {
                guard sectionName(for: sectionKeyString) == section else { continue }
                for identifier in savedIdentifiers where !allCurrentIdentifiers.contains(identifier) {
                    if !identifiers.contains(identifier) {
                        identifiers.append(identifier)
                    }
                }
            }

            if !identifiers.isEmpty {
                newOrder[sectionKey(for: section)] = identifiers
            }
        }

        guard newOrder != savedSectionOrder else { return }
        savedSectionOrder = newOrder
        persistSavedSectionOrder()
        MenuBarItemManager.diagLog.debug("Saved section order: \(newOrder.mapValues(\.count))")
    }

    /// Returns a persistable string key for the given section name.
    private func sectionKey(for section: MenuBarSection.Name) -> String {
        switch section {
        case .visible: "visible"
        case .hidden: "hidden"
        case .alwaysHidden: "alwaysHidden"
        }
    }

    /// Returns the section name for the given persisted key, if valid.
    private func sectionName(for key: String) -> MenuBarSection.Name? {
        switch key {
        case "visible": .visible
        case "hidden": .hidden
        case "alwaysHidden": .alwaysHidden
        default: nil
        }
    }

    private(set) weak var appState: AppState?

    /// Sets up the manager.
    func performSetup(with appState: AppState) async {
        MenuBarItemManager.diagLog.debug("performSetup: starting MenuBarItemManager setup")
        self.appState = appState
        loadKnownItemIdentifiers()
        loadPinnedBundleIDs()
        loadPendingRelocations()
        loadSavedSectionOrder()
        MenuBarItemManager.diagLog.debug("performSetup: loaded \(knownItemIdentifiers.count) known identifiers, \(pinnedHiddenBundleIDs.count) pinned hidden, \(pinnedAlwaysHiddenBundleIDs.count) pinned always-hidden, \(savedSectionOrder.values.map(\.count)) saved order entries")
        // On first launch (no known identifiers), avoid auto-relocating the leftmost item
        // so everything remains in the hidden section until the user interacts.
        suppressNextNewLeftmostItemRelocation = knownItemIdentifiers.isEmpty
        MenuBarItemManager.diagLog.debug("performSetup: calling initial cacheItemsRegardless")
        await cacheItemsRegardless()
        MenuBarItemManager.diagLog.debug("performSetup: initial cache complete, items in cache: visible=\(itemCache[.visible].count), hidden=\(itemCache[.hidden].count), alwaysHidden=\(itemCache[.alwaysHidden].count), managedItems=\(itemCache.managedItems.count)")
        configureCancellables(with: appState)
        MenuBarItemManager.diagLog.debug("performSetup: MenuBarItemManager setup complete")
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables(with appState: AppState) {
        var c = Set<AnyCancellable>()

        // When any app launches, refresh the cache to detect new menu bar items
        // (e.g., apps with "unremembered" icons that need restoration) and restore
        // any items that moved to incorrect sections after their app restarted.
        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )
        .debounce(for: 1, scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            MenuBarItemManager.diagLog.debug("App launched, refreshing cache for potential new items")
            Task {
                await self.cacheItemsRegardless()
            }
        }
        .store(in: &c)

        // When any app terminates, refresh the cache (items may have disappeared).
        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )
        .debounce(for: 1, scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            MenuBarItemManager.diagLog.debug("App terminated, refreshing cache")
            Task {
                await self.cacheItemsIfNeeded()
            }
        }
        .store(in: &c)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didActivateApplicationNotification
        )
        .debounce(for: 0.5, scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else {
                return
            }
            Task {
                await self.cacheItemsIfNeeded()
            }
        }
        .store(in: &c)

        appState.navigationState.$settingsNavigationIdentifier
            .sink { [weak self] identifier in
                guard let self, identifier == .menuBarLayout else {
                    return
                }
                Task {
                    await self.appState?.imageCache.updateCache(sections: MenuBarSection.Name.allCases)
                }
            }
            .store(in: &c)

        // When Settings reopens with Menu Bar Layout already selected,
        // settingsNavigationIdentifier does not change, so the subscriber
        // above does not fire. Observe isSettingsPresented to catch this case.
        appState.navigationState.$isSettingsPresented
            .removeDuplicates()
            .sink { [weak self] isPresented in
                guard
                    let self,
                    isPresented,
                    appState.navigationState.settingsNavigationIdentifier == .menuBarLayout
                else {
                    return
                }
                Task {
                    await self.appState?.imageCache.updateCache(sections: MenuBarSection.Name.allCases)
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns a Boolean value that indicates whether the most recent
    /// menu bar item move operation occurred within the given duration.
    func lastMoveOperationOccurred(within duration: Duration) -> Bool {
        guard let timestamp = lastMoveOperationTimestamp else {
            return false
        }
        return timestamp.duration(to: .now) <= duration
    }

    /// Records that a move operation occurred outside of Thaw's own `move()` function
    /// (e.g. the user cmd+dragged an item directly on the menu bar).
    func recordExternalMoveOperation() {
        lastMoveOperationTimestamp = .now
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// An actor that manages menu bar item cache operations.
    private final actor CacheActor {
        /// Stored task for the current cache operation.
        private var cacheTask: Task<Void, Never>?

        /// A list of the menu bar item window identifiers at the time
        /// of the previous cache.
        private(set) var cachedItemWindowIDs = [CGWindowID]()

        /// Runs the given async closure as a task and waits for it to
        /// complete before returning.
        ///
        /// If a task from a previous call to this method is currently
        /// running, that task is cancelled and replaced.
        func runCacheTask(_ operation: @escaping () async -> Void) async {
            cacheTask.take()?.cancel()
            let task = Task(operation: operation)
            cacheTask = task
            await task.value
        }

        /// Updates the list of cached menu bar item window identifiers.
        func updateCachedItemWindowIDs(_ itemWindowIDs: [CGWindowID]) {
            cachedItemWindowIDs = itemWindowIDs
        }

        /// Clears the list of cached menu bar item window identifiers.
        func clearCachedItemWindowIDs() {
            cachedItemWindowIDs.removeAll()
        }
    }

    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        /// Storage for cached menu bar items, keyed by section.
        private var storage = [MenuBarSection.Name: [MenuBarItem]]()

        /// The identifier of the display with the active menu bar at
        /// the time this cache was created.
        let displayID: CGDirectDisplayID?

        /// The cached menu bar items as an array.
        var managedItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                guard let items = storage[section] else {
                    return
                }
                result.append(contentsOf: items)
            }
        }

        /// Creates a cache with the given display identifier.
        init(displayID: CGDirectDisplayID?) {
            self.displayID = displayID
        }

        /// Returns the managed menu bar items for the given section.
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
            self[section]
        }

        /// Returns the address for the menu bar item with the given tag,
        /// if it exists in the cache.
        func address(for tag: MenuBarItemTag) -> (section: MenuBarSection.Name, index: Int)? {
            for (section, items) in storage {
                guard let index = items.firstIndex(matching: tag) else {
                    continue
                }
                return (section, index)
            }
            return nil
        }

        /// Inserts the given menu bar item into the cache at the specified
        /// destination.
        mutating func insert(_ item: MenuBarItem, at destination: MoveDestination) {
            let targetTag = destination.targetItem.tag

            if targetTag == .hiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.hidden].append(item)
                case .rightOfItem:
                    self[.visible].insert(item, at: 0)
                }
                return
            }

            if targetTag == .alwaysHiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.alwaysHidden].append(item)
                case .rightOfItem:
                    self[.hidden].insert(item, at: 0)
                }
                return
            }

            guard case (let section, var index)? = address(for: targetTag) else {
                return
            }

            if case .rightOfItem = destination {
                let range = self[section].startIndex ... self[section].endIndex
                index = (index + 1).clamped(to: range)
            }

            self[section].insert(item, at: index)
        }

        /// Accesses the items in the given section.
        subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
            get { storage[section, default: []] }
            set { storage[section] = newValue }
        }
    }

    /// A pair of control items, taken from a list of menu bar items
    /// during a menu bar item cache operation.
    private struct ControlItemPair {
        let hidden: MenuBarItem
        let alwaysHidden: MenuBarItem?

        /// Creates a control item pair from a list of menu bar items.
        ///
        /// The initializer first attempts a tag-based lookup (namespace + title).
        /// If that fails it falls back to matching by the current process PID and
        /// known control-item titles, and finally to matching by known window IDs.
        ///
        /// On macOS 26 (Tahoe), all menu bar item windows are owned by Control
        /// Center and the item title reported by `kCGWindowName` may differ from
        /// the `NSStatusItem` autosaveName used to build the expected tag, so the
        /// primary lookup can fail.
        init?(
            items: inout [MenuBarItem],
            hiddenControlItemWindowID: CGWindowID? = nil,
            alwaysHiddenControlItemWindowID: CGWindowID? = nil
        ) {
            // Primary lookup: match by tag (namespace + title).
            if let hidden = items.removeFirst(matching: .hiddenControlItem) {
                self.hidden = hidden
                self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
                return
            }

            // Fallback 1: match by sourcePID (our own process) + known title.
            let ourPID = ProcessInfo.processInfo.processIdentifier
            let hiddenTitle = ControlItem.Identifier.hidden.rawValue
            let alwaysHiddenTitle = ControlItem.Identifier.alwaysHidden.rawValue

            if let idx = items.firstIndex(where: { $0.sourcePID == ourPID && $0.title == hiddenTitle }) {
                self.hidden = items.remove(at: idx)
                if let ahIdx = items.firstIndex(where: { $0.sourcePID == ourPID && $0.title == alwaysHiddenTitle }) {
                    self.alwaysHidden = items.remove(at: ahIdx)
                } else {
                    self.alwaysHidden = nil
                }
                return
            }

            // Fallback 2: match by known window IDs obtained from the ControlItem
            // objects themselves. This handles the case where both the tag and the
            // window title are unreliable on macOS 26.
            if let hiddenWID = hiddenControlItemWindowID,
               let idx = items.firstIndex(where: { $0.windowID == hiddenWID })
            {
                self.hidden = items.remove(at: idx)
                if let ahWID = alwaysHiddenControlItemWindowID,
                   let ahIdx = items.firstIndex(where: { $0.windowID == ahWID })
                {
                    self.alwaysHidden = items.remove(at: ahIdx)
                } else {
                    self.alwaysHidden = nil
                }
                return
            }

            return nil
        }
    }

    /// Context maintained during a menu bar item cache operation.
    private struct CacheContext {
        let controlItems: ControlItemPair

        var cache: ItemCache
        var temporarilyShownItems = [(MenuBarItem, MoveDestination)]()
        var shouldClearCachedItemWindowIDs = false
        var relocatedItems = [MenuBarItem]()

        private(set) lazy var hiddenControlItemBounds = bestBounds(for: controlItems.hidden)
        private(set) lazy var alwaysHiddenControlItemBounds = controlItems.alwaysHidden.map(bestBounds)

        init(controlItems: ControlItemPair, displayID: CGDirectDisplayID?) {
            self.controlItems = controlItems
            self.cache = ItemCache(displayID: displayID)
        }

        func bestBounds(for item: MenuBarItem) -> CGRect {
            Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        }

        func isValidForCaching(_ item: MenuBarItem) -> Bool {
            if item.tag == .visibleControlItem {
                return true
            }
            if !item.canBeHidden {
                return false
            }
            if item.isSystemClone {
                return false
            }
            if item.isControlItem, item.tag != .visibleControlItem {
                return false
            }
            return true
        }

        mutating func findSection(for item: MenuBarItem) -> MenuBarSection.Name? {
            lazy var itemBounds = bestBounds(for: item)
            return MenuBarSection.Name.allCases.first { section in
                switch section {
                case .visible:
                    return itemBounds.minX >= hiddenControlItemBounds.maxX
                case .hidden:
                    if let alwaysHiddenControlItemBounds {
                        return itemBounds.maxX <= hiddenControlItemBounds.minX &&
                            itemBounds.minX >= alwaysHiddenControlItemBounds.maxX
                    } else {
                        return itemBounds.maxX <= hiddenControlItemBounds.minX
                    }
                case .alwaysHidden:
                    if let alwaysHiddenControlItemBounds {
                        return itemBounds.maxX <= alwaysHiddenControlItemBounds.minX
                    } else {
                        return false
                    }
                }
            }
        }
    }

    /// Caches the given menu bar items, without ensuring that the provided
    /// control items are correctly ordered.
    private func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?
    ) async {
        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: processing \(items.count) items for caching")
        var context = CacheContext(controlItems: controlItems, displayID: displayID)

        var validCount = 0
        var invalidCount = 0
        var noSectionCount = 0

        // Track which tags have already been cached to avoid duplicates.
        // macOS can briefly report two windows for the same item during
        // or shortly after a move operation (e.g. layout reset). We keep
        // the first occurrence, which is the rightmost (items are reversed
        // from the Window Server order).
        var seenTags = Set<MenuBarItemTag>()

        for item in items where context.isValidForCaching(item) {
            guard seenTags.insert(item.tag).inserted else {
                MenuBarItemManager.diagLog.debug("uncheckedCacheItems: skipping duplicate tag \(item.logString)")
                continue
            }

            validCount += 1
            if item.sourcePID == nil {
                MenuBarItemManager.diagLog.warning("Missing sourcePID for \(item.logString)")
            }

            let matchingContext: TemporarilyShownItemContext? = {
                // 1. Try exact tag match (includes windowID for non-system items).
                if let temp = temporarilyShownItemContexts.first(where: { $0.tag == item.tag }) {
                    return temp
                }
                // 2. Fallback: tag and PID match, but ONLY if the item is physically in the visible section
                //    (identifying it as the 'shown' instance) and it originally belonged elsewhere.
                if let temp = temporarilyShownItemContexts.first(where: {
                    $0.tag.matchesIgnoringWindowID(item.tag) &&
                        $0.sourcePID == (item.sourcePID ?? item.ownerPID)
                }) {
                    if context.findSection(for: item) == .visible, temp.originalSection != .visible {
                        return temp
                    }
                }
                return nil
            }()

            if let matchingContext {
                // Cache temporarily shown items as if they were in their original locations.
                // Keep track of them separately and use their return destinations to insert
                // them into the cache once all other items have been handled.
                context.temporarilyShownItems.append((item, matchingContext.returnDestination))
                continue
            }

            if let section = context.findSection(for: item) {
                context.cache[section].append(item)
                continue
            }

            noSectionCount += 1
            MenuBarItemManager.diagLog.warning("Couldn't find section for caching \(item.logString) bounds=\(NSStringFromRect(item.bounds))")
            context.shouldClearCachedItemWindowIDs = true
        }

        // Count invalid items
        for item in items where !context.isValidForCaching(item) {
            invalidCount += 1
        }

        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: \(validCount) valid, \(invalidCount) invalid (filtered), \(noSectionCount) couldn't find section, \(context.temporarilyShownItems.count) temporarily shown")

        for (item, destination) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination)
        }

        if context.shouldClearCachedItemWindowIDs {
            MenuBarItemManager.diagLog.info("Clearing cached menu bar item windowIDs")
            await cacheActor.clearCachedItemWindowIDs() // Ensure next cache isn't skipped.
        }

        guard itemCache != context.cache else {
            MenuBarItemManager.diagLog.debug("Not updating menu bar item cache, as items haven't changed")
            return
        }

        itemCache = context.cache

        // Reset isRestoringItemOrder if it's been stuck for too long (10 seconds).
        // This prevents stale flags from blocking saves after user manual moves.
        if isRestoringItemOrder, let timestamp = isRestoringItemOrderTimestamp, Date().timeIntervalSince(timestamp) > 10 {
            MenuBarItemManager.diagLog.debug("Resetting stale isRestoringItemOrder flag (timeout)")
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        if !isRestoringItemOrder, !isResettingLayout {
            saveSectionOrder(from: context.cache)
        }
        MenuBarItemManager.diagLog.debug("Updated menu bar item cache: visible=\(context.cache[.visible].count), hidden=\(context.cache[.hidden].count), alwaysHidden=\(context.cache[.alwaysHidden].count)")
    }

    /// Caches the current menu bar items, regardless of whether the
    /// items have changed since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsRegardless(
        _ currentItemWindowIDs: [CGWindowID]? = nil,
        skipRecentMoveCheck: Bool = false
    ) async {
        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: entering (skipRecentMoveCheck=\(skipRecentMoveCheck), hasCurrentItemWindowIDs=\(currentItemWindowIDs != nil))")
        await cacheActor.runCacheTask { [weak self] in
            defer {
                self?.backgroundCacheContinuation?.resume()
                self?.backgroundCacheContinuation = nil
            }

            guard let self else {
                MenuBarItemManager.diagLog.warning("cacheItemsRegardless: self is nil, aborting")
                return
            }

            guard skipRecentMoveCheck || !lastMoveOperationOccurred(within: .seconds(1)) else {
                MenuBarItemManager.diagLog.debug("Skipping menu bar item cache due to recent item movement")
                return
            }

            guard !(appState?.isDraggingMenuBarItem ?? false) else {
                MenuBarItemManager.diagLog.debug("Skipping menu bar item cache: user is cmd-dragging")
                return
            }

            let previousWindowIDs = await cacheActor.cachedItemWindowIDs
            let displayID = Bridging.getActiveMenuBarDisplayID()
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: displayID=\(displayID.map { "\($0)" } ?? "nil"), previousWindowIDs count=\(previousWindowIDs.count)")

            var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

            if items.isEmpty {
                // Retry once after a small delay if we got zero items. This can happen
                // due to transient WindowServer glitches or during display reconfigurations.
                MenuBarItemManager.diagLog.warning("cacheItemsRegardless: getMenuBarItems returned ZERO items, retrying in 250ms...")
                try? await Task.sleep(for: .milliseconds(250))
                items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            }

            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: getMenuBarItems returned \(items.count) items")

            if items.isEmpty {
                MenuBarItemManager.diagLog.error("cacheItemsRegardless: getMenuBarItems returned ZERO items even after retry — this is the root cause of 'Loading menu bar items' being stuck")
            }

            let itemWindowIDs = currentItemWindowIDs ?? items.reversed().map { $0.windowID }
            await cacheActor.updateCachedItemWindowIDs(itemWindowIDs)

            await MainActor.run {
                MenuBarItemTag.Namespace.pruneUUIDCache(keeping: Set(itemWindowIDs))
                self.pruneMoveOperationTimeouts(keeping: Set(items.map(\.tag)))
                self.pruneClickOperationTimeouts(keeping: Set(items.map(\.tag)))
            }

            for item in items {
                MenuBarItemManager.diagLog.debug("cacheItemsRegardless: item tag=\(item.tag) title=\(item.title ?? "nil") windowID=\(item.windowID) sourcePID=\(item.sourcePID.map { "\($0)" } ?? "nil") ownerPID=\(item.ownerPID)")
            }

            // Obtain window IDs from the actual ControlItem objects so the
            // fallback lookup in ControlItemPair can match by window ID when
            // the tag-based and title-based lookups fail (macOS 26+).
            let hiddenControlItemWID: CGWindowID? = appState?.menuBarManager
                .controlItem(withName: .hidden)?.window
                .flatMap { CGWindowID(exactly: $0.windowNumber) }
            let alwaysHiddenControlItemWID: CGWindowID? = appState?.menuBarManager
                .controlItem(withName: .alwaysHidden)?.window
                .flatMap { CGWindowID(exactly: $0.windowNumber) }

            guard let controlItems = ControlItemPair(
                items: &items,
                hiddenControlItemWindowID: hiddenControlItemWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWID
            ) else {
                // ???: Is clearing the cache the best thing to do here?
                MenuBarItemManager.diagLog.warning("cacheItemsRegardless: Missing control item for hidden section (expected tag: \(MenuBarItemTag.hiddenControlItem)), clearing cache. Items remaining: \(items.count), windowIDs: \(itemWindowIDs.count). hiddenControlItemWID=\(hiddenControlItemWID.map { "\($0)" } ?? "nil"), alwaysHiddenControlItemWID=\(alwaysHiddenControlItemWID.map { "\($0)" } ?? "nil")")
                await MainActor.run {
                    self.areControlItemsMissing = true
                }
                itemCache = ItemCache(displayID: nil)
                return
            }

            await MainActor.run {
                self.areControlItemsMissing = false
            }

            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: found control items, hidden windowID=\(controlItems.hidden.windowID), alwaysHidden=\(controlItems.alwaysHidden.map { "\($0.windowID)" } ?? "nil")")

            await enforceControlItemOrder(controlItems: controlItems)

            if await relocateNewLeftmostItems(
                items,
                controlItems: controlItems,
                previousWindowIDs: previousWindowIDs
            ) {
                MenuBarItemManager.diagLog.debug("Relocated new leftmost items; scheduling recache")
                let continuation = self.backgroundCacheContinuation
                self.backgroundCacheContinuation = nil
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
                    continuation?.resume()
                }
                return
            }

            if await relocatePendingItems(items, controlItems: controlItems) {
                MenuBarItemManager.diagLog.debug("Relocated pending temporarily-shown items; scheduling recache")
                let continuation = self.backgroundCacheContinuation
                self.backgroundCacheContinuation = nil
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
                    continuation?.resume()
                }
                return
            }

            // Cross-section restore: move items back to their saved section
            // before restoreSavedItemOrder handles within-section reordering.
            // Set the flag before calling so that any intermediate cache
            // updates during move() don't overwrite the saved section order.
            isRestoringItemOrder = true
            isRestoringItemOrderTimestamp = Date()
            let didRestoreSections = await restoreItemsToSavedSections(
                items,
                controlItems: controlItems,
                previousWindowIDs: previousWindowIDs
            )
            if didRestoreSections {
                MenuBarItemManager.diagLog.debug("Restored item to saved section; scheduling recache")
                let continuation = self.backgroundCacheContinuation
                self.backgroundCacheContinuation = nil
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
                    self?.isRestoringItemOrder = false
                    continuation?.resume()
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsIfNeeded()
                }
                return
            } else {
                isRestoringItemOrder = false
            }

            let didRestoreOrder = await restoreSavedItemOrder(
                items,
                controlItems: controlItems,
                previousWindowIDs: previousWindowIDs
            )

            if didRestoreOrder {
                // Keep isRestoringItemOrder true through the recache to prevent
                // saving intermediate item positions while macOS settles the moves.
                isRestoringItemOrder = true
                isRestoringItemOrderTimestamp = Date()
                MenuBarItemManager.diagLog.debug("Restored saved item order; scheduling recache")
                let continuation = self.backgroundCacheContinuation
                self.backgroundCacheContinuation = nil
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
                    self?.isRestoringItemOrder = false
                    continuation?.resume()
                    // Pick up items that appeared during the lock period
                    // (e.g. a second app launching concurrently).
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsIfNeeded()
                }
                return
            }

            await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: finished, cache now has \(self.itemCache.managedItems.count) managed items")
        }
    }

    /// Caches the current menu bar items, if the items have changed
    /// since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsIfNeeded() async {
        let itemWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
        let cachedIDs = await cacheActor.cachedItemWindowIDs
        if cachedIDs != itemWindowIDs {
            MenuBarItemManager.diagLog.debug("cacheItemsIfNeeded: window IDs changed (\(cachedIDs.count) cached vs \(itemWindowIDs.count) current), triggering recache")
            await cacheItemsRegardless(itemWindowIDs)
        }
    }
}

// MARK: - Event Helpers

extension MenuBarItemManager {
    /// An error that can occur during menu bar item event operations.
    enum EventError: CustomStringConvertible, LocalizedError {
        /// A generic indication of a failure.
        case cannotComplete
        /// An event source cannot be created or is otherwise invalid.
        case invalidEventSource
        /// The location of the mouse cannot be found.
        case missingMouseLocation
        /// A failure during the creation of an event.
        case eventCreationFailure(MenuBarItem)
        /// A timeout during an event operation.
        case eventOperationTimeout(MenuBarItem)
        /// A menu bar item is not movable.
        case itemNotMovable(MenuBarItem)
        /// A timeout waiting for a menu bar item to respond to an event.
        case itemResponseTimeout(MenuBarItem)
        /// A menu bar item's bounds cannot be found.
        case missingItemBounds(MenuBarItem)

        var description: String {
            switch self {
            case .cannotComplete:
                "\(Self.self).cannotComplete"
            case .invalidEventSource:
                "\(Self.self).invalidEventSource"
            case .missingMouseLocation:
                "\(Self.self).missingMouseLocation"
            case let .eventCreationFailure(item):
                "\(Self.self).eventCreationFailure(item: \(item.tag))"
            case let .eventOperationTimeout(item):
                "\(Self.self).eventOperationTimeout(item: \(item.tag))"
            case let .itemNotMovable(item):
                "\(Self.self).itemNotMovable(item: \(item.tag))"
            case let .itemResponseTimeout(item):
                "\(Self.self).itemResponseTimeout(item: \(item.tag))"
            case let .missingItemBounds(item):
                "\(Self.self).missingItemBounds(item: \(item.tag))"
            }
        }

        var errorDescription: String? {
            switch self {
            case .cannotComplete:
                "Operation could not be completed"
            case .invalidEventSource:
                "Invalid event source"
            case .missingMouseLocation:
                "Missing mouse location"
            case let .eventCreationFailure(item):
                "Could not create event for \"\(item.displayName)\""
            case let .eventOperationTimeout(item):
                "Event operation timed out for \"\(item.displayName)\""
            case let .itemNotMovable(item):
                "\"\(item.displayName)\" is not movable"
            case let .itemResponseTimeout(item):
                "\"\(item.displayName)\" took too long to respond"
            case let .missingItemBounds(item):
                "Missing bounds rectangle for \"\(item.displayName)\""
            }
        }

        var recoverySuggestion: String? {
            if case .itemNotMovable = self { return nil }
            return "Please try again. If the error persists, please file a bug report."
        }
    }

    /// Returns a Boolean value that indicates whether the user has
    /// paused input for at least the given duration.
    ///
    /// - Parameter duration: The duration that certain types of input
    ///   events must not have occured within in order to return `true`.
    private nonisolated func hasUserPausedInput(for duration: Duration) -> Bool {
        NSEvent.modifierFlags.isEmpty &&
            !MouseHelpers.lastMovementOccurred(within: duration) &&
            !MouseHelpers.lastScrollWheelOccurred(within: duration) &&
            !MouseHelpers.isButtonPressed()
    }

    /// Waits asynchronously for the user to pause input.
    private nonisolated func waitForUserToPauseInput() async throws {
        let waitTask = Task {
            while true {
                try Task.checkCancellation()
                if hasUserPausedInput(for: .milliseconds(50)) {
                    break
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        do {
            try await waitTask.value
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Waits between move operations for a dynamic amount of time,
    /// based on the timestamp of the last move operation.
    private nonisolated func waitForMoveOperationBuffer() async throws {
        if let timestamp = await lastMoveOperationTimestamp {
            let buffer = max(.milliseconds(25) - timestamp.duration(to: .now), .zero)
            MenuBarItemManager.diagLog.debug("Move operation buffer: \(buffer)")
            do {
                try await Task.sleep(for: buffer)
            } catch {
                throw EventError.cannotComplete
            }
        }
    }

    /// Waits for the given duration between event operations.
    ///
    /// Since most event operations must perform cleanup or otherwise
    /// run to completion, this method ignores task cancellation.
    private nonisolated func eventSleep(for duration: Duration = .milliseconds(25)) async {
        let task = Task {
            try? await Task.sleep(for: duration)
        }
        await task.value
    }

    /// Returns the current bounds for the given item, with a refresh fallback if the window is missing.
    private nonisolated func getCurrentBounds(for item: MenuBarItem) async throws -> CGRect {
        // First attempt: current windowID.
        if let bounds = Bridging.getWindowBounds(for: item.windowID) {
            return bounds
        }

        // Fallback: refresh on-screen items and pick the matching tag (prefer same windowID, then non-clone).
        let refreshed = await MenuBarItem.getMenuBarItems(option: .onScreen)
        if let refreshedItem = refreshed.first(where: { $0.windowID == item.windowID && $0.tag == item.tag }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) && !$0.isSystemClone }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) })
        {
            return refreshedItem.bounds
        }

        throw EventError.missingItemBounds(item)
    }

    /// Returns the current mouse location.
    private nonisolated func getMouseLocation() throws -> CGPoint {
        guard let location = MouseHelpers.locationCoreGraphics else {
            throw EventError.missingMouseLocation
        }
        return location
    }

    /// Returns the process identifier that can be used to create
    /// and post a menu bar item event.
    private nonisolated func getEventPID(for item: MenuBarItem) -> pid_t {
        item.sourcePID ?? item.ownerPID
    }

    /// Returns an event source for a menu bar item event operation.
    private nonisolated func getEventSource(
        with stateID: CGEventSourceStateID = .hidSystemState
    ) throws -> CGEventSource {
        enum Context {
            static var cache = [CGEventSourceStateID: CGEventSource]()
        }
        if let source = Context.cache[stateID] {
            return source
        }
        guard let source = CGEventSource(stateID: stateID) else {
            throw EventError.invalidEventSource
        }
        Context.cache[stateID] = source
        return source
    }

    /// Prevents local events from being suppressed.
    private nonisolated func permitLocalEvents() throws {
        let source = try getEventSource(with: .combinedSessionState)
        let states: [CGEventSuppressionState] = [
            .eventSuppressionStateRemoteMouseDrag,
            .eventSuppressionStateSuppressionInterval,
        ]
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = 0
    }

    /// Posts an event to the given menu bar item and waits until
    /// it is received before returning.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `postEventWithBarrier`.
    private nonisolated func postEventWithBarrier(
        _ event: CGEvent,
        to item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw EventError.eventCreationFailure(item)
        }

        let pid = getEventPID(for: item)
        event.setTargetPID(pid)

        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        var count = count
        var eventTaps = [EventTap]()

        defer {
            for tap in eventTaps {
                tap.invalidate()
            }
        }

        // Outer-scope locks so the onCancel handler can unblock the stuck
        // continuation directly. innerTask completes almost immediately after
        // enabling the EventTaps; by the time the timeout fires, cancelling
        // innerTask is a no-op. The outer onCancel must therefore resume the
        // continuation itself to prevent withThrowingTaskGroup from waiting
        // forever and holding eventSemaphore for 5 seconds.
        let didResume = OSAllocatedUnfairLock(initialState: false)
        let continuationHolder = OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>(initialState: nil)
        let innerTaskHolder = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

        let timeoutTask = Task(timeout: timeout * count) {
            try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Store continuation so the outer onCancel handler can resume it directly.
                continuationHolder.withLock { $0 = continuation }

                // Listen for the following events at the first location
                // and perform the following actions:
                //
                // - Entry event: Decrement the count and post the real
                //   event to the second location (handled in EventTap 2).
                // - Exit event: Resume the continuation.
                //
                // These events serve as start (or continue) and stop
                // signals, and are discarded.
                let eventTap1 = EventTap(
                    label: "EventTap 1",
                    type: .null,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .defaultTap
                ) { tap, rEvent in
                    if rEvent.matches(entryEvent, byIntegerFields: [.eventSourceUserData]) {
                        count -= 1
                        event.post(to: secondLocation)
                        return nil
                    }
                    if rEvent.matches(exitEvent, byIntegerFields: [.eventSourceUserData]) {
                        tap.disable()
                        if didResume.tryClaimOnce() {
                            continuation.resume()
                        }
                        return nil
                    }
                    return rEvent
                }

                // Listen for the real event at the second location and,
                // depending on the count, post either the entry or exit
                // event to the first location (handled in EventTap 1).
                let eventTap2 = EventTap(
                    label: "EventTap 2",
                    type: event.type,
                    location: secondLocation,
                    placement: .tailAppendEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }
                    if count <= 0 {
                        tap.disable()
                        exitEvent.post(to: firstLocation)
                    } else {
                        entryEvent.post(to: firstLocation)
                    }
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                // Keep the taps alive.
                eventTaps.append(eventTap1)
                eventTaps.append(eventTap2)

                let innerTask = Task {
                    await withTaskCancellationHandler {
                        eventTap1.enable()
                        eventTap2.enable()
                        entryEvent.post(to: firstLocation)
                    } onCancel: {
                        eventTap1.disable()
                        eventTap2.disable()
                        if didResume.tryClaimOnce() {
                            continuation.resume(throwing: CancellationError())
                        }
                    }
                }
                innerTaskHolder.withLock { $0 = innerTask }
                // Handle race: outer task may have been cancelled before innerTask was stored.
                if Task.isCancelled { innerTask.cancel() }
            }
            } onCancel: {
                innerTaskHolder.withLock { $0 }?.cancel()
                // Directly resume the continuation — handles the common case where
                // innerTask already finished before cancellation was delivered.
                let cont = continuationHolder.withLock { $0 }
                if let cont, didResume.tryClaimOnce() {
                    cont.resume(throwing: CancellationError())
                }
            }
        }
        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError.eventOperationTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Casts forbidden magic to make a menu bar item receive and
    /// respond to an event during a move operation.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `scrombleEvent`.
    private nonisolated func scrombleEvent(
        _ event: CGEvent,
        item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw EventError.eventCreationFailure(item)
        }

        let pid = getEventPID(for: item)
        event.setTargetPID(pid)

        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        var count = count
        var eventTaps = [EventTap]()

        defer {
            for tap in eventTaps {
                tap.invalidate()
            }
        }

        // Outer-scope locks so the onCancel handler can unblock the stuck
        // continuation directly. innerTask completes almost immediately after
        // enabling the EventTaps; by the time the timeout fires, cancelling
        // innerTask is a no-op. The outer onCancel must therefore resume the
        // continuation itself to prevent withThrowingTaskGroup from waiting
        // forever and holding eventSemaphore for 5 seconds.
        let didResume = OSAllocatedUnfairLock(initialState: false)
        let continuationHolder = OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>(initialState: nil)
        let innerTaskHolder = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

        let timeoutTask = Task(timeout: timeout * count) {
            try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Store continuation so the outer onCancel handler can resume it directly.
                continuationHolder.withLock { $0 = continuation }

                // Listen for the following events at the first location
                // and perform the following actions:
                //
                // - Entry event: Decrement the count and post the real
                //   event to the second location (handled in EventTap 2).
                // - Exit event: Resume the continuation.
                //
                // These events serve as start (or continue) and stop
                // signals, and are discarded.
                let eventTap1 = EventTap(
                    label: "EventTap 1",
                    type: .null,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .defaultTap
                ) { tap, rEvent in
                    if rEvent.matches(entryEvent, byIntegerFields: [.eventSourceUserData]) {
                        count -= 1
                        event.post(to: secondLocation)
                        return nil
                    }
                    if rEvent.matches(exitEvent, byIntegerFields: [.eventSourceUserData]) {
                        tap.disable()
                        if didResume.tryClaimOnce() {
                            continuation.resume()
                        }
                        return nil
                    }
                    return rEvent
                }

                // Listen for the real event at the second location and
                // post the real event to the first location (handled in
                // EventTap 3).
                let eventTap2 = EventTap(
                    label: "EventTap 2",
                    type: event.type,
                    location: secondLocation,
                    placement: .tailAppendEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }
                    if count <= 0 {
                        tap.disable()
                    }
                    event.post(to: firstLocation)
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                // Listen for the real event at the first location and,
                // depending on the count, post either the entry or exit
                // event to the first location (handled in EventTap 1).
                let eventTap3 = EventTap(
                    label: "EventTap 3",
                    type: event.type,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }
                    if count <= 0 {
                        tap.disable()
                        exitEvent.post(to: firstLocation)
                    } else {
                        entryEvent.post(to: firstLocation)
                    }
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                // Keep the taps alive.
                eventTaps.append(eventTap1)
                eventTaps.append(eventTap2)
                eventTaps.append(eventTap3)

                let innerTask = Task {
                    await withTaskCancellationHandler {
                        eventTap1.enable()
                        eventTap2.enable()
                        eventTap3.enable()
                        entryEvent.post(to: firstLocation)
                    } onCancel: {
                        eventTap1.disable()
                        eventTap2.disable()
                        eventTap3.disable()
                        if didResume.tryClaimOnce() {
                            continuation.resume(throwing: CancellationError())
                        }
                    }
                }
                innerTaskHolder.withLock { $0 = innerTask }
                // Handle race: outer task may have been cancelled before innerTask was stored.
                if Task.isCancelled { innerTask.cancel() }
            }
            } onCancel: {
                innerTaskHolder.withLock { $0 }?.cancel()
                // Directly resume the continuation — handles the common case where
                // innerTask already finished before cancellation was delivered.
                let cont = continuationHolder.withLock { $0 }
                if let cont, didResume.tryClaimOnce() {
                    cont.resume(throwing: CancellationError())
                }
            }
        }
        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError.eventOperationTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }
}

// MARK: - Moving Items

extension MenuBarItemManager {
    /// Destinations for menu bar item move operations.
    enum MoveDestination {
        /// The destination to the left of the given target item.
        case leftOfItem(MenuBarItem)
        /// The destination to the right of the given target item.
        case rightOfItem(MenuBarItem)

        /// The destination's target item.
        var targetItem: MenuBarItem {
            switch self {
            case let .leftOfItem(item), let .rightOfItem(item): item
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case let .leftOfItem(item): "left of \(item.logString)"
            case let .rightOfItem(item): "right of \(item.logString)"
            }
        }
    }

    /// Returns the default timeout for move operations associated
    /// with the given item.
    private func getDefaultMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if item.isBentoBox {
            // Bento Boxes (i.e. Control Center groups) generally
            // take a little longer to respond.
            return .milliseconds(200)
        }
        return .milliseconds(100)
    }

    /// Returns the cached timeout for move operations associated
    /// with the given item.
    private func getMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = moveOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultMoveOperationTimeout(for: item)
    }

    /// Updates the cached timeout for move operations associated
    /// with the given item.
    private func updateMoveOperationTimeout(_ timeout: Duration, for item: MenuBarItem) {
        let current = getMoveOperationTimeout(for: item)
        let average = (timeout + current) / 2
        // Minimum of 75ms: waitForMoveEventResponse polls every 10ms, so a
        // timeout below ~75ms leaves too little margin for system event latency
        // and causes itemResponseTimeout → retry cascades.
        let clamped = average.clamped(min: .milliseconds(75), max: .milliseconds(500))
        moveOperationTimeouts[item.tag] = clamped
    }

    /// Prunes the move operation timeouts cache, keeping only the entries
    /// for the given valid tags.
    private func pruneMoveOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        moveOperationTimeouts = moveOperationTimeouts.filter { validTags.contains($0.key) }
    }
    
    /// Returns the default timeout for click operations based on the item's namespace.
    private func getDefaultClickOperationTimeout(for item: MenuBarItem) -> Duration {
        // Known slow apps with dynamic content
        let slowAppBundleIDs = [
            "com.bitsplash.PasteNow",
            "com.charliemonroe.Downie-setapp",
            "com.if.Amphetamine",
            "com.hegenberg.BetterTouchTool",
            "net.matthewpalmer.Vanilla",
        ]
        
        let namespaceString = item.tag.namespace.description
        if slowAppBundleIDs.contains(where: { namespaceString.contains($0) }) {
            return .milliseconds(500) // Extra time for slow apps
        }
        
        return .milliseconds(350) // Default
    }
    
    /// Returns the cached timeout for click operations associated with the given item.
    private func getClickOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = clickOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultClickOperationTimeout(for: item)
    }
    
    /// Updates the cached timeout for click operations associated with the given item.
    private func updateClickOperationTimeout(_ duration: Duration, for item: MenuBarItem) {
        let current = getClickOperationTimeout(for: item)
        let average = (duration + current) / 2
        let clamped = average.clamped(min: .milliseconds(200), max: .milliseconds(1000))
        clickOperationTimeouts[item.tag] = clamped
        MenuBarItemManager.diagLog.debug("Updated click timeout for \(item.logString): \(Int(clamped.milliseconds))ms (measured: \(Int(duration.milliseconds))ms)")
    }
    
    /// Prunes the click operation timeouts cache, keeping only the entries
    /// for the given valid tags.
    private func pruneClickOperationTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        clickOperationTimeouts = clickOperationTimeouts.filter { validTags.contains($0.key) }
    }

    /// Returns the target points for creating the events needed to
    /// move a menu bar item to the given destination.
    private nonisolated func getTargetPoints(
        forMoving item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async throws -> (start: CGPoint, end: CGPoint) {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)

        let start: CGPoint
        let end: CGPoint

        switch destination {
        case .leftOfItem:
            start = CGPoint(x: targetBounds.minX, y: targetBounds.minY)
            end = start
        case .rightOfItem:
            start = CGPoint(x: targetBounds.maxX, y: targetBounds.minY)
            end = start
        }

        MenuBarItemManager.diagLog.debug(
            "Move points: startX=\(start.x) endX=\(end.x) startY=\(start.y) targetMinX=\(targetBounds.minX) itemMinX=\(itemBounds.minX) targetTag=\(destination.targetItem.tag) itemTag=\(item.tag) display=\(displayID)"
        )
        return (start, end)
    }

    /// Returns a Boolean value that indicates whether the given menu bar
    /// item has the correct position, relative to the given destination.
    private nonisolated func itemHasCorrectPosition(
        item: MenuBarItem,
        for destination: MoveDestination,
        on _: CGDirectDisplayID
    ) async throws -> Bool {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        return switch destination {
        case .leftOfItem: itemBounds.maxX == targetBounds.minX
        case .rightOfItem: itemBounds.minX == targetBounds.maxX
        }
    }

    /// Waits for a menu bar item to respond to a series of previously
    /// posted move events.
    ///
    /// - Parameters:
    ///   - item: The item to check for a response.
    ///   - initialOrigin: The origin of the item before the events were posted.
    ///   - timeout: The duration to wait before throwing an error.
    private nonisolated func waitForMoveEventResponse(
        from item: MenuBarItem,
        initialOrigin: CGPoint,
        timeout: Duration
    ) async throws -> CGPoint {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }
        let responseTask = Task.detached {
            while true {
                try Task.checkCancellation()
                let origin = try await self.getCurrentBounds(for: item).origin
                if origin != initialOrigin {
                    return origin
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let timeoutTask = Task(timeout: timeout) {
            try await withTaskCancellationHandler {
                try await responseTask.value
            } onCancel: {
                responseTask.cancel()
            }
        }
        do {
            let origin = try await timeoutTask.value
            MenuBarItemManager.diagLog.debug(
                """
                Item responded to events with new origin: \
                \(String(describing: origin))
                """
            )
            return origin
        } catch let error as EventError {
            throw error
        } catch is TaskTimeoutError {
            throw EventError.itemResponseTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Creates and posts a series of events to move a menu bar item
    /// to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    private func postMoveEvents(
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async throws {
        do {
            try await eventSemaphore.wait(timeout: .seconds(5))
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error("eventSemaphore timed out in postMoveEvents, forcing signal and retrying")
            await eventSemaphore.signal()
            throw EventError.cannotComplete
        }
        defer { Task.detached { [eventSemaphore] in await eventSemaphore.signal() } }

        var itemOrigin = try await getCurrentBounds(for: item).origin
        let targetPoints = try await getTargetPoints(forMoving: item, to: destination, on: displayID)
        let mouseLocation = try getMouseLocation()
        let source = try getEventSource()

        try permitLocalEvents()

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .move(.mouseDown),
                location: targetPoints.start
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: destination.targetItem,
                source: source,
                type: .move(.mouseUp),
                location: targetPoints.end
            )
        else {
            throw EventError.eventCreationFailure(item)
        }

        var timeout = getMoveOperationTimeout(for: item)
        MenuBarItemManager.diagLog.debug("Move operation timeout: \(timeout)")

        lastMoveOperationTimestamp = .now
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
            lastMoveOperationTimestamp = .now
            updateMoveOperationTimeout(timeout, for: item)
        }

        do {
            try await scrombleEvent(
                mouseDown,
                item: item,
                timeout: timeout
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            try await scrombleEvent(
                mouseUp,
                item: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            timeout -= timeout / 4
        } catch {
            do {
                MenuBarItemManager.diagLog.warning("Move events failed, posting fallback")
                try await scrombleEvent(
                    mouseUp,
                    item: item,
                    timeout: .milliseconds(100), // Fixed timeout for fallback.
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                MenuBarItemManager.diagLog.error("Fallback failed with error: \(error)")
            }
            timeout += timeout / 2
            throw error
        }
    }

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the item to.
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: CGDirectDisplayID? = nil,
        skipInputPause: Bool = false,
        watchdogTimeout: DispatchTimeInterval? = nil
    ) async throws {
        guard item.isMovable else {
            throw EventError.itemNotMovable(item)
        }
        guard let appState else {
            throw EventError.cannotComplete
        }

        // Determine display ID early.
        let resolvedDisplayID: CGDirectDisplayID
        if let displayID = displayID {
            resolvedDisplayID = displayID
        } else if let window = appState.hidEventManager.bestScreen(appState: appState) {
            resolvedDisplayID = window.displayID
        } else {
            resolvedDisplayID = Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        }

        if !skipInputPause {
            try await waitForUserToPauseInput()
        }
        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        try await waitForMoveOperationBuffer()

        MenuBarItemManager.diagLog.info(
            """
            Moving \(item.logString) to \
            \(destination.logString) on display \(resolvedDisplayID)
            """
        )

        guard try await !itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID) else {
            MenuBarItemManager.diagLog.debug("Item has correct position, cancelling move")
            return
        }

        MouseHelpers.hideCursor(watchdogTimeout: watchdogTimeout)
        defer {
            MouseHelpers.showCursor()
        }

        let maxAttempts = 8
        for n in 1 ... maxAttempts {
            guard !Task.isCancelled else {
                throw EventError.cannotComplete
            }
            do {
                if try await itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID) {
                    MenuBarItemManager.diagLog.debug("Item has correct position, finished with move")
                    return
                }
                try await postMoveEvents(item: item, destination: destination, on: resolvedDisplayID)
                // Verify the item actually reached the correct position.
                if try await itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID) {
                    MenuBarItemManager.diagLog.debug("Attempt \(n) succeeded and verified, finished with move")
                    return
                }
                MenuBarItemManager.diagLog.debug("Attempt \(n) events succeeded but item not at destination, retrying")
                if n < maxAttempts {
                    try await waitForMoveOperationBuffer()
                    continue
                }
            } catch {
                MenuBarItemManager.diagLog.debug("Attempt \(n) failed: \(error)")
                if n < maxAttempts {
                    try await waitForMoveOperationBuffer()
                    continue
                }
                if error is EventError {
                    throw error
                }
                throw EventError.cannotComplete
            }
        }
    }
}

// MARK: - Clicking Items

extension MenuBarItemManager {
    /// Returns the equivalent event subtypes for clicking a menu bar
    /// item with the given mouse button.
    private nonisolated func getClickSubtypes(
        for mouseButton: CGMouseButton
    ) -> (down: MenuBarItemEventType.ClickSubtype, up: MenuBarItemEventType.ClickSubtype) {
        switch mouseButton {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
    }

    /// Creates and posts a series of events to click a menu bar item.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    private func postClickEvents(item: MenuBarItem, mouseButton: CGMouseButton) async throws {
        // Try to acquire semaphore with timeout
        do {
            try await eventSemaphore.wait(timeout: .seconds(5))
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error("eventSemaphore timed out in postClickEvents for \(item.logString), forcing signal and retrying")
            await eventSemaphore.signal()
            throw EventError.cannotComplete
        }
        defer { Task.detached { [eventSemaphore] in await eventSemaphore.signal() } }

        let clickPoint = try await getCurrentBounds(for: item).center
        let mouseLocation = try getMouseLocation()
        let source = try getEventSource()

        try permitLocalEvents()

        let clickTypes = getClickSubtypes(for: mouseButton)
        // Use adaptive timeout based on app performance history
        let timeout = getClickOperationTimeout(for: item)
        
        MenuBarItemManager.diagLog.debug("postClickEvents: using timeout \(Int(timeout.milliseconds))ms for \(item.logString)")

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.down),
                location: clickPoint
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.up),
                location: clickPoint
            )
        else {
            throw EventError.eventCreationFailure(item)
        }

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
        }

        let eventStartTime = Date.now
        do {
            try await postEventWithBarrier(
                mouseDown,
                to: item,
                timeout: timeout
            )
            try await postEventWithBarrier(
                mouseUp,
                to: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
            
            // Update timeout cache with successful duration
            let successDuration = Duration.milliseconds(Date.now.timeIntervalSince(eventStartTime) * 1000)
            updateClickOperationTimeout(successDuration, for: item)
        } catch {
            do {
                MenuBarItemManager.diagLog.warning("Click events failed, posting fallback")
                try await postEventWithBarrier(
                    mouseUp,
                    to: item,
                    timeout: timeout,
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                MenuBarItemManager.diagLog.error("Fallback failed with error: \(error)")
            }
            throw error
        }
    }

    /// Clicks a menu bar item with the given mouse button.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    func click(item: MenuBarItem, with mouseButton: CGMouseButton, skipInputPause: Bool = false) async throws {
        guard let appState else {
            throw EventError.cannotComplete
        }

        if !skipInputPause {
            try await waitForUserToPauseInput()
        }

        MenuBarItemManager.diagLog.info(
            """
            Clicking \(item.logString) with \
            \(mouseButton.logString)
            """
        )

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        let maxAttempts = 3  // Reduced from 4 to minimize accumulated delay
        let attemptStartTime = Date.now
        for n in 1 ... maxAttempts {
            guard !Task.isCancelled else {
                throw EventError.cannotComplete
            }
            do {
                let clickStartTime = Date.now
                try await postClickEvents(item: item, mouseButton: mouseButton)
                let clickDuration = Date.now.timeIntervalSince(clickStartTime)
                MenuBarItemManager.diagLog.debug("Attempt \(n) succeeded in \(Int(clickDuration * 1000))ms, finished with click")
                return
            } catch {
                let attemptDuration = Date.now.timeIntervalSince(attemptStartTime)
                MenuBarItemManager.diagLog.debug("Attempt \(n) failed after \(Int(attemptDuration * 1000))ms: \(error)")
                if n < maxAttempts {
                    await eventSleep()
                    continue
                }
                if error is EventError {
                    throw error
                }
                throw EventError.cannotComplete
            }
        }
    }
}

// MARK: - Temporarily Showing Items

extension MenuBarItemManager {
    /// Context for a temporarily shown menu bar item.
    private final class TemporarilyShownItemContext {
        /// The tag associated with the item.
        let tag: MenuBarItemTag

        /// The PID of the application that owns this item, used to detect
        /// nonstandard popup windows that ``shownInterfaceWindow`` may miss.
        let sourcePID: pid_t

        /// The display identifier where the item was shown.
        let displayID: CGDirectDisplayID

        /// The destination to return the item to (captured at show-time).
        /// This is the preferred destination, but may become stale if the
        /// target item has moved or disappeared by the time we rehide.
        let returnDestination: MoveDestination

        /// The tag of the neighbor on the opposite side of
        /// ``returnDestination``, used as a secondary fallback to preserve
        /// relative ordering when the primary target is gone.
        let fallbackNeighborTag: MenuBarItemTag?

        /// The PID of the neighbor on the opposite side.
        let fallbackNeighborPID: pid_t?

        /// The original section the item belonged to before being temporarily
        /// shown. Used as a last-resort fallback when both neighbor-based
        /// destinations are stale.
        let originalSection: MenuBarSection.Name

        /// The window of the item's shown interface.
        var shownInterfaceWindow: WindowInfo?

        /// The number of attempts that have been made to rehide the item.
        var rehideAttempts = 0

        /// The number of times the item was not found on the active space.
        /// Tracked separately from ``rehideAttempts`` to allow more retries
        /// for the "item not found" case (the app may be on another space
        /// or temporarily invisible).
        var notFoundAttempts = 0

        /// Timestamp for when the item was first shown so we can honor
        /// a short grace period for menus that use nonstandard windows.
        private let firstShownDate = Date.now

        /// Minimum time to treat the item as "showing" even if we can't
        /// detect a popup window (helps apps with unusual window levels).
        private let graceInterval: TimeInterval = 2

        /// A Boolean value that indicates whether the menu bar item's
        /// interface is showing.
        var isShowingInterface: Bool {
            // First check the tracked popup window — this is the most
            // reliable signal when available.
            if let window = shownInterfaceWindow,
               let current = WindowInfo(windowID: window.windowID)
            {
                if current.layer == CGWindowLevelForKey(.popUpMenuWindow)
                    || current.layer == CGWindowLevelForKey(.popUpMenuWindow) - 1
                    || current.layer == CGWindowLevelForKey(.statusWindow)
                    || current.layer == CGWindowLevelForKey(.mainMenuWindow)
                {
                    return current.isOnScreen
                }
                if let app = current.owningApplication {
                    return app.isActive && current.isOnScreen
                }
                return current.isOnScreen
            }

            // The tracked window is gone or was never captured. During the
            // grace period, assume the interface is still showing to give
            // apps with nonstandard windows time to create them.
            if Date.now.timeIntervalSince(firstShownDate) < graceInterval {
                return true
            }

            // Grace period expired and no tracked window. Check whether the
            // app has any visible popup or overlay window that we missed.
            return appHasVisiblePopup()
        }

        /// Checks whether the item's owning application has any visible
        /// popup, menu, or overlay window on screen.
        private func appHasVisiblePopup() -> Bool {
            let windows = WindowInfo.createWindows(option: .onScreen)
            return windows.contains { window in
                guard window.ownerPID == sourcePID else {
                    return false
                }
                // Menu-level or status-level windows are popups.
                if window.isMenuRelated {
                    return true
                }
                // Above-normal layer windows (overlays, popovers) that
                // belong to the app also count.
                if window.layer > CGWindowLevelForKey(.normalWindow) {
                    return true
                }
                return false
            }
        }

        init(
            tag: MenuBarItemTag,
            sourcePID: pid_t,
            displayID: CGDirectDisplayID,
            returnDestination: MoveDestination,
            fallbackNeighborTag: MenuBarItemTag?,
            fallbackNeighborPID: pid_t?,
            originalSection: MenuBarSection.Name
        ) {
            self.tag = tag
            self.sourcePID = sourcePID
            self.displayID = displayID
            self.returnDestination = returnDestination
            self.fallbackNeighborTag = fallbackNeighborTag
            self.fallbackNeighborPID = fallbackNeighborPID
            self.originalSection = originalSection
        }
    }

    /// Gets the destination to return the given item to after it is
    /// temporarily shown, along with the tag and PID of the neighbor on the
    /// opposite side (if any) for fallback ordering.
    private func getReturnDestination(
        for item: MenuBarItem,
        in items: [MenuBarItem]
    ) -> (destination: MoveDestination, fallbackNeighbor: (tag: MenuBarItemTag, pid: pid_t)?)? {
        guard let index = items.firstIndex(matching: item.tag) else {
            return nil
        }
        // Prefer anchoring to the item on the right (lower index = further
        // right in macOS menu bar coordinates). The fallback is the item on
        // the opposite side.
        if items.indices.contains(index + 1) {
            let neighbor = items[index + 1]
            let fallback: (MenuBarItemTag, pid_t)? = if items.indices.contains(index - 1) {
                (items[index - 1].tag, items[index - 1].sourcePID ?? items[index - 1].ownerPID)
            } else {
                nil
            }
            return (.leftOfItem(neighbor), fallback)
        }
        if items.indices.contains(index - 1) {
            let neighbor = items[index - 1]
            return (.rightOfItem(neighbor), nil)
        }
        return nil
    }

    /// Waits for a menu bar item's position to stabilize after a move.
    ///
    /// After a Cmd+drag move, the Window Server updates the item's window
    /// position, but the owning app may take additional time to process the
    /// change internally. If we click the item before it has settled, the
    /// app may position its popup at the old location.
    ///
    /// This method polls the item's bounds until two consecutive reads
    /// return the same value, up to a maximum wait time.
    private nonisolated func waitForItemPositionToSettle(item: MenuBarItem) async {
        let maxWait: Duration = .milliseconds(250)
        let pollInterval: Duration = .milliseconds(20)
        let startTime = ContinuousClock.now

        var previousBounds = Bridging.getWindowBounds(for: item.windowID)

        while ContinuousClock.now - startTime < maxWait {
            await eventSleep(for: pollInterval)
            let currentBounds = Bridging.getWindowBounds(for: item.windowID)
            if currentBounds == previousBounds, currentBounds != nil {
                return
            }
            previousBounds = currentBounds
        }
    }

    /// Schedules a timer for the given interval that rehides the
    /// temporarily shown items when fired.
    private func runRehideTimer(for interval: TimeInterval? = nil) {
        let interval = interval ?? 15
        MenuBarItemManager.diagLog.debug("Running rehide timer for interval: \(interval)")
        rehideTimer?.invalidate()
        rehideCancellable?.cancel()
        rehideTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MenuBarItemManager.diagLog.debug("Rehide timer fired")
            Task {
                await self.rehideTemporarilyShownItems()
            }
        }
        // Also rehide when frontmost app changes (smart-ish).
        rehideCancellable = NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.rehideTemporarilyShownItems() }
            }
    }

    /// Temporarily shows the given item.
    ///
    /// The item is cached and returned to its original location after approximately
    /// 15 seconds, though it may be sooner (e.g., when switching apps) or later
    /// due to the smart rehide logic (e.g., +1s for recent user input, +3s when
    /// a menu is open).
    ///
    /// - Parameters:
    ///   - item: The item to temporarily show.
    ///   - mouseButton: The mouse button to click the item with.
    ///   - displayID: The display identifier to show the item on.
    func temporarilyShow(item: MenuBarItem, clickingWith mouseButton: CGMouseButton, on displayID: CGDirectDisplayID? = nil) async {
        guard let appState else {
            MenuBarItemManager.diagLog.error("Missing AppState, so not showing \(item.logString)")
            return
        }

        MenuBarItemManager.diagLog.debug("temporarilyShow: started for \(item.logString)")

        // Determine the displayID for this item.
        let resolvedDisplayID: CGDirectDisplayID
        if let displayID {
            resolvedDisplayID = displayID
        } else {
            let itemBounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
            let screen = NSScreen.screens.first { $0.frame.intersects(itemBounds) }
            resolvedDisplayID = screen?.displayID ?? Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        }

        // Determine the item's original section early so we can persist it
        // and use it as a fallback if the neighbor-based return destination
        // becomes stale by the time we rehide.
        let originalSection = itemCache.address(for: item.tag)?.section ?? .hidden
        let tagIdentifier = "\(item.tag.namespace):\(item.tag.title)"

        // Rehide any previously temporarily shown items before showing a new one.
        // This prevents stale contexts from accumulating when the user opens multiple
        // temporary items in quick succession.
        if !temporarilyShownItemContexts.isEmpty {
            rehideTimer?.invalidate()
            rehideCancellable?.cancel()
            await rehideTemporarilyShownItems(force: true, isCalledFromTemporarilyShow: true)

            // If some items failed to rehide (e.g. move timed out), don't remove
            // them from the contexts list. They will be retried by the rehide timer
            // or the next temporarilyShow call.
            if temporarilyShownItemContexts.contains(where: { $0.tag.matchesIgnoringWindowID(item.tag) }) {
                // The item we want to show is already in the temporary list.
                // This can happen if the user clicks the same item twice very fast.
                // Remove the old context so we can create a fresh one with new bounds.
                removeTemporarilyShownItemFromCache(with: item.tag)
            }
        }

        // Fetch items specifically for the display where the item lives.
        let items = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .activeSpace)

        guard let returnInfo = getReturnDestination(for: item, in: items) else {
            MenuBarItemManager.diagLog.error("No return destination for \(item.logString) on display \(resolvedDisplayID)")
            return
        }

        // Prefer inserting to the left of the Thaw/visible control item so the icon appears
        // where users expect. If it's missing, fall back to the first non-control item.
        let visibleControl = items.first(matching: .visibleControlItem)
        let targetItem = visibleControl ?? items.first(where: { !$0.isControlItem && $0.canBeHidden }) ?? items.first

        // If we couldn't find any anchor, bail gracefully.
        guard let anchor = targetItem else {
            MenuBarItemManager.diagLog.warning("Not enough room or no anchor to show \(item.logString)")
            let alert = NSAlert()
            alert.messageText = String(localized: "Not enough room to show \"\(item.displayName)\"")
            alert.runModal()
            return
        }

        let moveDestination: MoveDestination = .leftOfItem(anchor)

        // Record the item's original section early so we can relocate it if its app
        // quits before we get a chance to rehide it (macOS persists the
        // physical position set by the Cmd+drag, so on relaunch the icon
        // would otherwise stay in the visible section).
        pendingRelocations[tagIdentifier] = sectionKey(for: originalSection)

        // Also store the return destination to preserve ordering
        let neighborTag = returnInfo.destination.targetItem.tag
        let position: String
        switch returnInfo.destination {
        case .leftOfItem: position = "left"
        case .rightOfItem: position = "right"
        }
        pendingReturnDestinations[tagIdentifier] = [
            "neighbor": "\(neighborTag.namespace):\(neighborTag.title)",
            "position": position,
        ]
        persistPendingRelocations()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        MenuBarItemManager.diagLog.debug("Temporarily showing \(item.logString) on display \(resolvedDisplayID)")

        do {
            try await move(item: item, to: moveDestination, on: resolvedDisplayID, skipInputPause: true)
        } catch {
            MenuBarItemManager.diagLog.error("Error showing item: \(error)")
            pendingRelocations.removeValue(forKey: tagIdentifier)
            pendingReturnDestinations.removeValue(forKey: tagIdentifier)
            persistPendingRelocations()
            return
        }

        let context = TemporarilyShownItemContext(
            tag: item.tag,
            sourcePID: item.sourcePID ?? item.ownerPID,
            displayID: resolvedDisplayID,
            returnDestination: returnInfo.destination,
            fallbackNeighborTag: returnInfo.fallbackNeighbor?.tag,
            fallbackNeighborPID: returnInfo.fallbackNeighbor?.pid,
            originalSection: originalSection
        )
        temporarilyShownItemContexts.append(context)

        rehideTimer?.invalidate()
        defer {
            runRehideTimer()
        }

        // Wait for the item's position to stabilize after the move. Some
        // apps need time to process the window relocation before they can
        // correctly position their popup in response to a click.
        await waitForItemPositionToSettle(item: item)

        // Re-fetch the item from the live window list specifically for this display.
        // Prefer an exact windowID match, then fall back to namespace+title with PID matching.
        let refreshedItems = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .onScreen)
        let clickItem = refreshedItems.first(where: { $0.windowID == item.windowID }) ??
            refreshedItems.first(where: {
                $0.tag.matchesIgnoringWindowID(item.tag) &&
                    ($0.sourcePID ?? $0.ownerPID) == (item.sourcePID ?? item.ownerPID)
            }) ?? item

        // Give the owning app a little extra time to finish processing the
        // move internally. Some apps (e.g. OneDrive) need more than just a
        // stable window position before they can respond to clicks.
        await eventSleep(for: .milliseconds(25))

        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))

        do {
            try await click(item: clickItem, with: mouseButton, skipInputPause: true)
        } catch {
            MenuBarItemManager.diagLog.error("Error clicking item: \(error)")
            return
        }

        await eventSleep(for: .milliseconds(100))
        let windowsAfterClick = WindowInfo.createWindows(option: .onScreen)

        let clickPID = clickItem.sourcePID ?? clickItem.ownerPID
        context.shownInterfaceWindow = windowsAfterClick.first { window in
            window.ownerPID == clickPID && !idsBeforeClick.contains(window.windowID)
        }
    }

    /// Resolves the best move destination for returning a temporarily shown
    /// item to its original section.
    ///
    /// Tries destinations in order of preference:
    /// 1. The captured ``TemporarilyShownItemContext/returnDestination``
    ///    (primary neighbor, refreshed with current bounds).
    /// 2. The ``TemporarilyShownItemContext/fallbackNeighborTag`` (the
    ///    neighbor on the opposite side, to preserve relative ordering).
    /// 3. The control item for the item's original section (guarantees
    ///    the item ends up in the correct section, though ordering within
    ///    the section may differ).
    private func resolveReturnDestination(
        for context: TemporarilyShownItemContext,
        in items: [MenuBarItem]
    ) -> MoveDestination? {
        // 1. Try the primary neighbor-based destination.
        //    Re-wrap with the fresh item so the move uses current bounds.
        let targetTag = context.returnDestination.targetItem.tag
        let targetPID = context.returnDestination.targetItem.sourcePID ?? context.returnDestination.targetItem.ownerPID
        if let freshTarget = items.first(where: {
            $0.tag.matchesIgnoringWindowID(targetTag) &&
                ($0.sourcePID ?? $0.ownerPID) == targetPID
        }) {
            switch context.returnDestination {
            case .leftOfItem:
                return .leftOfItem(freshTarget)
            case .rightOfItem:
                return .rightOfItem(freshTarget)
            }
        }

        // 2. Try the fallback neighbor (opposite side).
        if let fallbackTag = context.fallbackNeighborTag,
           let fallbackPID = context.fallbackNeighborPID
        {
            if let freshFallback = items.first(where: {
                $0.tag.matchesIgnoringWindowID(fallbackTag) &&
                    ($0.sourcePID ?? $0.ownerPID) == fallbackPID
            }) {
                switch context.returnDestination {
                case .leftOfItem:
                    return .rightOfItem(freshFallback)
                case .rightOfItem:
                    return .leftOfItem(freshFallback)
                }
            }
        }

        // 3. Fallback: use the control item for the original section.
        MenuBarItemManager.diagLog.debug(
            """
            Return destination neighbors not found for \(context.tag); \
            falling back to section-level destination for \(context.originalSection.logString)
            """
        )
        switch context.originalSection {
        case .hidden:
            if let controlItem = items.first(matching: .hiddenControlItem) {
                return .leftOfItem(controlItem)
            }
        case .alwaysHidden:
            if let controlItem = items.first(matching: .alwaysHiddenControlItem) {
                return .leftOfItem(controlItem)
            }
            // If the always-hidden section was disabled, fall back to hidden.
            if let controlItem = items.first(matching: .hiddenControlItem) {
                return .leftOfItem(controlItem)
            }
        case .visible:
            // Should not happen (we don't temporarily show items that are
            // already visible), but handle it gracefully.
            return nil
        }

        MenuBarItemManager.diagLog.error("No control items found to resolve return destination for \(context.tag)")
        return nil
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its interface, this method waits
    /// for the interface to close before hiding the items, unless `force`
    /// is `true`, in which case all items are rehidden immediately.
    ///
    /// - Parameter force: If `true`, skip the interface-showing and
    ///   user-input guards and rehide all items immediately.
    func rehideTemporarilyShownItems(force: Bool = false, isCalledFromTemporarilyShow: Bool = false) async {
        guard let appState else {
            MenuBarItemManager.diagLog.error("Missing AppState, so not rehiding")
            return
        }
        guard !temporarilyShownItemContexts.isEmpty else {
            return
        }

        MenuBarItemManager.diagLog.debug("rehideTemporarilyShownItems: started (force=\(force), isCalledFromTemporarilyShow=\(isCalledFromTemporarilyShow))")

        if !force {
            guard !temporarilyShownItemContexts.contains(where: { $0.isShowingInterface }) else {
                MenuBarItemManager.diagLog.debug("Menu bar item interface is shown, so waiting to rehide")
                runRehideTimer(for: 3)
                return
            }
            guard hasUserPausedInput(for: .milliseconds(250)) else {
                MenuBarItemManager.diagLog.debug("Found recent user input, so waiting to rehide")
                runRehideTimer(for: 1)
                return
            }
        }

        var currentContexts = temporarilyShownItemContexts
        temporarilyShownItemContexts.removeAll()

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedContexts = [TemporarilyShownItemContext]()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        // Use a shorter settle time when called from temporarilyShow — the user
        // is actively waiting for the next click. The eventSemaphore and
        // waitForMoveOperationBuffer in move() provide adequate race protection.
        await eventSleep(for: isCalledFromTemporarilyShow ? .milliseconds(50) : .milliseconds(250))

        MenuBarItemManager.diagLog.debug("Rehiding temporarily shown items")

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        while let context = currentContexts.popLast() {
            guard let item = items.first(where: {
                $0.tag.matchesIgnoringWindowID(context.tag) &&
                    ($0.sourcePID ?? $0.ownerPID) == context.sourcePID
            }) else {
                context.notFoundAttempts += 1
                MenuBarItemManager.diagLog.debug(
                    """
                    Missing temporarily shown item \(context.tag) on active space \
                    (not-found attempt \(context.notFoundAttempts)); will retry
                    """
                )
                // Keep the context for retry — the item may be on another
                // space or the app may have briefly hidden it. After enough
                // attempts, drop the in-memory context and rely on the
                // persisted pendingRelocations entry to recover on the next
                // cache cycle (relocatePendingItems).
                if context.notFoundAttempts < 10 {
                    failedContexts.append(context)
                } else {
                    MenuBarItemManager.diagLog.warning(
                        """
                        Giving up in-memory retry for \(context.tag) after \
                        \(context.notFoundAttempts) not-found attempts; \
                        pendingRelocations will handle recovery
                        """
                    )
                }
                continue
            }

            // Resolve the best return destination using fresh items.
            guard let destination = resolveReturnDestination(for: context, in: items) else {
                MenuBarItemManager.diagLog.error(
                    """
                    Could not resolve return destination for \(item.logString); \
                    item will remain in visible section until next cache cycle handles pendingRelocations
                    """
                )
                // Don't remove pendingRelocations — let relocatePendingItems handle it.
                continue
            }

            do {
                try await move(item: item, to: destination, on: context.displayID, skipInputPause: true)
                // Successfully rehidden — remove the pending relocation entry.
                let tagIdentifier = "\(context.tag.namespace):\(context.tag.title)"
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
            } catch {
                context.rehideAttempts += 1
                MenuBarItemManager.diagLog.warning(
                    """
                    Attempt \(context.rehideAttempts) to rehide \
                    \(item.logString) failed with error: \
                    \(error)
                    """
                )
                if context.rehideAttempts < 3 {
                    currentContexts.append(context) // Try again immediately.
                } else {
                    // Move failed 3 times with the item present. Reset and
                    // schedule a longer-delay retry.
                    context.rehideAttempts = 0
                    failedContexts.append(context)
                }
            }
        }

        persistPendingRelocations()

        // If force-hiding, we don't want to re-queue them for long delays.
        // We want them back in the section immediately or kept in context.
        if failedContexts.isEmpty {
            MenuBarItemManager.diagLog.debug("All items were successfully rehidden")
        } else {
            MenuBarItemManager.diagLog.error(
                """
                Some items failed to rehide; keeping in context for retry: \
                \(failedContexts.map { $0.tag })
                """
            )
            temporarilyShownItemContexts.append(contentsOf: failedContexts.reversed())
            if !force {
                runRehideTimer(for: 3)
            }
        }
    }

    /// Removes a temporarily shown item from the cache, ensuring that
    /// the item is _not_ returned to its original location.
    func removeTemporarilyShownItemFromCache(with tag: MenuBarItemTag) {
        while let index = temporarilyShownItemContexts.firstIndex(where: { $0.tag.matchesIgnoringWindowID(tag) }) {
            MenuBarItemManager.diagLog.debug(
                """
                Removing temporarily shown item from cache: \
                \(tag)
                """
            )
            temporarilyShownItemContexts.remove(at: index)
        }
        // Also clear any pending relocation since the user explicitly
        // placed the item in a new position.
        let tagIdentifier = "\(tag.namespace):\(tag.title)"
        if pendingRelocations.removeValue(forKey: tagIdentifier) != nil {
            pendingReturnDestinations.removeValue(forKey: tagIdentifier)
            persistPendingRelocations()
        }
    }
}

// MARK: - Control Item Order

extension MenuBarItemManager {
    /// Relocates any newly appearing items that macOS placed to the left
    /// of our control items back into the visible section.
    ///
    /// Returns true if a relocation was performed.
    private func relocateNewLeftmostItems(
        _ items: [MenuBarItem],
        controlItems: ControlItemPair,
        previousWindowIDs: [CGWindowID]
    ) async -> Bool {
        guard appState != nil else { return false }

        if suppressNextNewLeftmostItemRelocation {
            // Seed known identifiers so these baseline items won't be treated as "new"
            // on subsequent cache passes, then clear the suppression flag.
            let identifiers = items
                .filter { !$0.isControlItem }
                .map { "\($0.tag.namespace):\($0.tag.title)" }
            knownItemIdentifiers.formUnion(identifiers)
            persistKnownItemIdentifiers()
            suppressNextNewLeftmostItemRelocation = false
            return false
        }

        // Avoid relocating items already assigned to hidden/always-hidden sections.
        let hiddenTags = Set(itemCache[.hidden].map(\.tag))
        let alwaysHiddenTags = Set(itemCache[.alwaysHidden].map(\.tag))

        /// Track bundle IDs for pinned items in hidden/always-hidden.
        func bundleID(for item: MenuBarItem) -> String? {
            item.sourceApplication?.bundleIdentifier ?? item.owningApplication?.bundleIdentifier
        }

        for item in itemCache[.hidden] {
            if let id = bundleID(for: item) {
                pinnedHiddenBundleIDs.insert(id)
            }
        }
        for item in itemCache[.alwaysHidden] {
            if let id = bundleID(for: item) {
                pinnedAlwaysHiddenBundleIDs.insert(id)
            }
        }
        persistPinnedBundleIDs()

        // Identify items that are to the left of the hidden control item bounds.
        let hiddenBounds = bestBounds(for: controlItems.hidden)
        let leftmostItems = items
            .filter {
                // Must be left of hidden divider, movable.
                // Include normal items AND the Thaw icon (which is a control item).
                $0.bounds.maxX <= hiddenBounds.minX &&
                    $0.isMovable &&
                    (!$0.isControlItem || $0.tag == .visibleControlItem)
            }
            .sorted { $0.bounds.minX < $1.bounds.minX }

        guard !leftmostItems.isEmpty else {
            return false
        }

        // The Thaw icon must always appear in the visible section.
        if let thawIcon = leftmostItems.first(where: { $0.tag == .visibleControlItem }) {
            MenuBarItemManager.diagLog.info("Relocating Thaw icon \(thawIcon.logString) to visible section")
            do {
                try await move(
                    item: thawIcon,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true
                )
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate Thaw icon \(thawIcon.logString): \(error)")
                return false
            }
            return true
        }

        // Non-hideable system items (screen recording, mic, camera indicators)
        // must always appear in the visible section. If macOS placed one to the
        // left of our hidden control item, move it back immediately — no
        // newness check needed since these items should never be in a hidden
        // section.
        if let systemItem = leftmostItems.first(where: { !$0.canBeHidden }) {
            MenuBarItemManager.diagLog.info("Relocating non-hideable system item \(systemItem.logString) to visible section")
            do {
                try await move(
                    item: systemItem,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true
                )
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate system item \(systemItem.logString): \(error)")
                return false
            }
            return true
        }

        // For hideable items, identify a candidate that is new (windowID or
        // tag/namespace) and not already placed/pinned in hidden areas.
        let hideableLeftmost = leftmostItems.filter { $0.canBeHidden }
        let previousIDs = Set(previousWindowIDs)

        // Build lookup for saved sections (same logic as restoreItemsToSavedSections).
        var savedSectionForIdentifier = [String: MenuBarSection.Name]()
        for (sectionKeyString, identifiers) in savedSectionOrder {
            guard let section = sectionName(for: sectionKeyString) else { continue }
            for identifier in identifiers {
                savedSectionForIdentifier[identifier] = section
            }
        }

        let candidate = hideableLeftmost.first { item in
            let identifier = "\(item.tag.namespace):\(item.tag.title)"

            // Only treat as "new" if we don't have a saved section for this item.
            // Items with saved sections should be handled by restoreItemsToSavedSections,
            // not by the "new item" relocation logic.
            let hasSavedSection = savedSectionForIdentifier[identifier] != nil ||
                savedSectionForIdentifier[item.uniqueIdentifier] != nil
            guard !hasSavedSection else { return false }

            let isNewIdentity = !knownItemIdentifiers.contains(identifier)
            let isNewID = previousIDs.isEmpty ? isNewIdentity : !previousIDs.contains(item.windowID)
            let notPlacedHidden = !hiddenTags.contains(item.tag) && !alwaysHiddenTags.contains(item.tag)
            let bundle = bundleID(for: item)
            let notPinnedHidden = bundle.map { !pinnedHiddenBundleIDs.contains($0) && !pinnedAlwaysHiddenBundleIDs.contains($0) } ?? true
            return notPlacedHidden && notPinnedHidden && (isNewID || isNewIdentity)
        }
        guard let candidate else {
            if !leftmostItems.isEmpty && savedSectionForIdentifier.isEmpty == false {
                MenuBarItemManager.diagLog.debug("relocateNewLeftmostItems: skipping, items have saved sections (letting restore handle it)")
            }
            return false
        }

        // Track this item so we don't move it again unless it truly appears new.
        let identifier = "\(candidate.tag.namespace):\(candidate.tag.title)"
        knownItemIdentifiers.insert(identifier)
        persistKnownItemIdentifiers()

        // Move only the offending item to the right of the hidden control item (i.e., into visible section).
        do {
            try await move(
                item: candidate,
                to: .rightOfItem(controlItems.hidden),
                skipInputPause: true
            )
        } catch {
            MenuBarItemManager.diagLog.error("Failed to relocate \(candidate.logString): \(error)")
            return false
        }

        return true
    }

    /// Relocates items whose apps quit while they were temporarily shown
    /// in the visible section back to their original section.
    ///
    /// When `temporarilyShow` moves an item to the visible section, macOS
    /// persists that position. If the app quits before rehide can move it
    /// back, the icon will reappear in the visible section on relaunch.
    /// This method checks for such items and moves them back.
    ///
    /// Returns `true` if any items were relocated.
    private func relocatePendingItems(
        _ items: [MenuBarItem],
        controlItems: ControlItemPair
    ) async -> Bool {
        guard !pendingRelocations.isEmpty else {
            return false
        }

        // Don't interfere with items that are currently temporarily shown —
        // those are handled by the normal rehide flow.
        let activelyShownTags = Set(temporarilyShownItemContexts.map {
            "\($0.tag.namespace):\($0.tag.title)"
        })

        let hiddenBounds = bestBounds(for: controlItems.hidden)
        var didRelocate = false

        for (tagIdentifier, sectionString) in pendingRelocations {
            guard !activelyShownTags.contains(tagIdentifier) else {
                continue
            }
            guard let targetSection = sectionName(for: sectionString),
                  targetSection != .visible
            else {
                // Nothing to do if the original section was visible.
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                continue
            }

            // Find the item in the current menu bar items.
            guard let item = items.first(where: {
                tagIdentifier == "\($0.tag.namespace):\($0.tag.title)"
            }) else {
                // Item not present yet (app hasn't relaunched). Keep the entry.
                continue
            }

            // Check if the item is currently in the visible section (to the
            // right of the hidden control item).
            let itemBounds = bestBounds(for: item)
            guard itemBounds.minX >= hiddenBounds.maxX else {
                // Item is already in a hidden section — clean up.
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                continue
            }

            // Move the item back to its original section.
            // Try to use the stored destination from the persisted data to preserve ordering.
            let destination: MoveDestination
            if let destInfo = pendingReturnDestinations[tagIdentifier],
               let neighborTagString = destInfo["neighbor"],
               let neighborItem = items.first(where: { neighborTagString == "\($0.tag.namespace):\($0.tag.title)" })
            {
                if destInfo["position"] == "left" {
                    destination = .leftOfItem(neighborItem)
                } else {
                    destination = .rightOfItem(neighborItem)
                }
            } else if let fallbackTagString = temporarilyShownItemContexts.first(where: { tagIdentifier == "\($0.tag.namespace):\($0.tag.title)" })?.fallbackNeighborTag,
                      let fallbackItem = items.first(matching: fallbackTagString)
            {
                destination = .rightOfItem(fallbackItem)
            } else {
                switch targetSection {
                case .hidden:
                    destination = .leftOfItem(controlItems.hidden)
                case .alwaysHidden:
                    if let alwaysHidden = controlItems.alwaysHidden {
                        destination = .leftOfItem(alwaysHidden)
                    } else {
                        destination = .leftOfItem(controlItems.hidden)
                    }
                case .visible:
                    continue
                }
            }

            MenuBarItemManager.diagLog.info(
                """
                Relocating \(item.logString) back to \
                \(targetSection.logString) after app relaunch
                """
            )

            do {
                try await move(item: item, to: destination, skipInputPause: true)
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                didRelocate = true
            } catch {
                MenuBarItemManager.diagLog.error(
                    """
                    Failed to relocate \(item.logString) back to \
                    \(targetSection.logString): \(error)
                    """
                )
            }
        }

        persistPendingRelocations()
        return didRelocate
    }

    /// Restores items to their saved sections when an app restarts and
    /// macOS places its items in a different section than where the user
    /// arranged them.
    ///
    /// `restoreSavedItemOrder` only reorders items *within* a section.
    /// This function handles the *cross-section* case: for example,
    /// Stats.app items that the user placed in the visible section but
    /// macOS put back in the hidden section upon relaunch.
    ///
    /// Returns `true` if any items were moved (caller should recache).
    private func restoreItemsToSavedSections(
        _ items: [MenuBarItem],
        controlItems: ControlItemPair,
        previousWindowIDs: [CGWindowID]
    ) async -> Bool {
        guard !savedSectionOrder.isEmpty else { return false }
        guard !suppressNextNewLeftmostItemRelocation else { return false }
        guard !lastMoveOperationOccurred(within: .seconds(2)) else { return false }

        // Only restore when previous window IDs have disappeared (app restarted).
        // This prevents undoing the user's manual section moves on regular cache refreshes.
        let currentWindowIDSet = Set(items.map(\.windowID))
        let previousWindowIDSet = Set(previousWindowIDs)
        guard !previousWindowIDSet.isEmpty && !previousWindowIDSet.isSubset(of: currentWindowIDSet) else {
            MenuBarItemManager.diagLog.debug("restoreItemsToSavedSections: no app restart detected (window IDs unchanged), skipping")
            return false
        }

        // Get current item tags.
        let currentTags = Set(items.map { "\($0.tag.namespace):\($0.tag.title)" })
        let savedTags = Set(savedSectionOrder.values.flatMap { $0 })
        let savedTagsInCurrent = savedTags.intersection(currentTags)

        // Only restore if saved items that were hidden/alwaysHidden are now visible,
        // or if items moved sections incorrectly after app restart.
        // Skip if no saved items are currently present (app closed).
        guard !savedTagsInCurrent.isEmpty else {
            MenuBarItemManager.diagLog.debug("restoreItemsToSavedSections: no saved items currently present, skipping")
            return false
        }

        // Give macOS time to settle after app restart before attempting moves.
        MenuBarItemManager.diagLog.debug("restoreItemsToSavedSections: waiting for menu bar to settle...")
        try? await Task.sleep(for: .milliseconds(500))

        // Build two lookups from savedSectionOrder:
        // 1. uniqueIdentifier → saved section (exact match)
        // 2. namespace string → saved section (fallback for dynamic-title apps)
        //
        // A namespace that appears in more than one section is ambiguous; we
        // remove it from the fallback map so we never guess wrong.
        var savedSectionForItem = [String: MenuBarSection.Name]()
        var savedSectionByNamespace = [String: MenuBarSection.Name]()
        var ambiguousNamespaces = Set<String>()
        for (sectionKeyString, identifiers) in savedSectionOrder {
            guard let section = sectionName(for: sectionKeyString) else { continue }
            for identifier in identifiers {
                savedSectionForItem[identifier] = section
                // Extract namespace (everything before the first ":").
                let ns = identifier.split(separator: ":", maxSplits: 1).first.map(String.init) ?? identifier
                if ambiguousNamespaces.contains(ns) {
                    // Already known to span multiple sections — skip.
                    continue
                }
                if let existing = savedSectionByNamespace[ns], existing != section {
                    // Namespace spans multiple sections — invalidate fallback.
                    savedSectionByNamespace.removeValue(forKey: ns)
                    ambiguousNamespaces.insert(ns)
                } else {
                    savedSectionByNamespace[ns] = section
                }
            }
        }

        // Classify current items by physical position.
        var context = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )

        // Don't interfere with temporarily shown items.
        let activelyShownTags = Set(temporarilyShownItemContexts.map {
            "\($0.tag.namespace):\($0.tag.title)"
        })

        for item in items where !item.isControlItem && item.isMovable && item.canBeHidden {
            let tagString = "\(item.tag.namespace):\(item.tag.title)"
            guard !activelyShownTags.contains(tagString) else { continue }

            guard let currentSection = context.findSection(for: item) else { continue }

            // Prefer exact match; fall back to namespace-only match for apps whose
            // item titles change on every appearance (e.g. Dato calendar events).
            let namespaceString = item.tag.namespace.description
            let savedSection: MenuBarSection.Name
            if let exact = savedSectionForItem[item.uniqueIdentifier] {
                savedSection = exact
            } else if DynamicItemOverrides.isDynamic(namespaceString),
                      let fallback = savedSectionByNamespace[namespaceString]
            {
                savedSection = fallback
            } else {
                continue
            }

            guard currentSection != savedSection else { continue }

            // Item is in the wrong section — move it.
            let destination: MoveDestination
            switch savedSection {
            case .visible:
                destination = .rightOfItem(controlItems.hidden)
            case .hidden:
                if let alwaysHidden = controlItems.alwaysHidden {
                    destination = .rightOfItem(alwaysHidden)
                } else {
                    destination = .leftOfItem(controlItems.hidden)
                }
            case .alwaysHidden:
                if let alwaysHidden = controlItems.alwaysHidden {
                    destination = .leftOfItem(alwaysHidden)
                } else {
                    destination = .leftOfItem(controlItems.hidden)
                }
            }

            MenuBarItemManager.diagLog.info(
                "Restoring \(item.logString) from \(currentSection.logString) to \(savedSection.logString)"
            )

            do {
                MenuBarItemManager.diagLog.debug("Starting move for restore: item=\(item.logString), destination=\(destination.logString)")
                try await move(item: item, to: destination, skipInputPause: true)
                MenuBarItemManager.diagLog.debug("Move completed successfully for restore")
            } catch let error as EventError {
                MenuBarItemManager.diagLog.error(
                    "Failed to restore \(item.logString) to \(savedSection.logString): \(error.errorDescription ?? error.description)"
                )
                continue
            } catch {
                MenuBarItemManager.diagLog.error(
                    "Failed to restore \(item.logString) to \(savedSection.logString): \(error)"
                )
                continue
            }

            // Return after first successful move and recache, like
            // relocateNewLeftmostItems. This lets macOS settle before
            // moving the next item.
            return true
        }

        MenuBarItemManager.diagLog.debug("restoreItemsToSavedSections: no items needed restoring (checked \(items.count) items)")
        return false
    }

    /// Only triggers when the set of window IDs has changed (items were
    /// recreated by an app restart), not when items were merely repositioned
    /// (user drag). This prevents undoing the user's manual reordering.
    ///
    /// - Note: For apps with dynamic item titles (see `DynamicItemOverrides`),
    ///   this function restores the **section** but not the intra-section order,
    ///   because the saved position key includes the old title which no longer
    ///   matches the new item.
    ///
    /// Returns `true` if any items were moved.
    private func restoreSavedItemOrder(
        _ items: [MenuBarItem],
        controlItems: ControlItemPair,
        previousWindowIDs: [CGWindowID]
    ) async -> Bool {
        guard !savedSectionOrder.isEmpty else { return false }

        // Don't attempt another restore while a previous restore's recache is in flight.
        guard !isRestoringItemOrder else { return false }

        // Don't restore while suppressing relocations (first launch / reset).
        guard !suppressNextNewLeftmostItemRelocation else { return false }

        // Don't restore when we recently performed our own move operations
        // (user drag in the Layout Bar, internal relocations, etc.). External
        // app restarts never go through our move() path, so their cache cycles
        // will have no recent move timestamp.
        guard !lastMoveOperationOccurred(within: .seconds(2)) else { return false }

        // Only restore when previous window IDs have disappeared, indicating
        // an app restarted (old windows destroyed, new ones created). During
        // move operations macOS can briefly report duplicate windows for the
        // same item, which adds transient IDs to the current set. Checking
        // for removed IDs (rather than any set difference) avoids false
        // positives from these duplicates and from user drag-and-drop, which
        // only repositions existing windows without removing any.
        let currentWindowIDSet = Set(items.lazy.map(\.windowID))
        let previousWindowIDSet = Set(previousWindowIDs)
        guard !previousWindowIDSet.isSubset(of: currentWindowIDSet) else { return false }

        // Don't interfere with items that are currently temporarily shown.
        let activelyShownTags = Set(temporarilyShownItemContexts.map {
            "\($0.tag.namespace):\($0.tag.title)"
        })

        // Build a lookup from uniqueIdentifier → MenuBarItem for all current non-control items.
        var itemsByID = [String: MenuBarItem]()
        for item in items where !item.isControlItem {
            itemsByID[item.uniqueIdentifier] = item
        }

        // Classify current items into sections using position-based detection.
        var context = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )
        var currentSectionItems = [String: [MenuBarItem]]()
        for item in items where !item.isControlItem && context.isValidForCaching(item) {
            if let section = context.findSection(for: item) {
                let key = sectionKey(for: section)
                currentSectionItems[key, default: []].append(item)
            }
        }

        var didMove = false

        for sectionName in MenuBarSection.Name.allCases {
            let sectionKeyString = sectionKey(for: sectionName)
            guard let savedIdentifiers = savedSectionOrder[sectionKeyString],
                  let currentItems = currentSectionItems[sectionKeyString],
                  !currentItems.isEmpty
            else {
                continue
            }

            // Filter saved identifiers to only those present in this section right now.
            let currentIDSet = Set(currentItems.map(\.uniqueIdentifier))
            let filteredSaved = savedIdentifiers.filter { currentIDSet.contains($0) }

            guard !filteredSaved.isEmpty else { continue }

            // Build the current order (identifiers only, preserving cache array order = right-to-left).
            let currentOrder = currentItems.map(\.uniqueIdentifier)

            // Skip section if the relative order of the overlapping items already matches.
            let filteredSavedSet = Set(filteredSaved)
            let currentFiltered = currentOrder.filter { filteredSavedSet.contains($0) }
            guard currentFiltered != filteredSaved else { continue }

            MenuBarItemManager.diagLog.info(
                """
                Restoring saved item order for \(sectionKeyString) section \
                (\(filteredSaved.count) items)
                """
            )

            // Find the first valid anchor that is not temporarily shown.
            var anchorIndex = 0
            var anchor: MenuBarItem?
            while anchorIndex < filteredSaved.count {
                guard let candidate = itemsByID[filteredSaved[anchorIndex]] else {
                    anchorIndex += 1
                    continue
                }
                let tagString = "\(candidate.tag.namespace):\(candidate.tag.title)"
                if activelyShownTags.contains(tagString) {
                    anchorIndex += 1
                    continue
                }
                anchor = candidate
                break
            }
            guard let anchor else { continue }

            // Move items right-to-left: the anchor is the rightmost valid item;
            // each subsequent item is placed to its left.
            var currentAnchor = anchor
            for i in (anchorIndex + 1) ..< filteredSaved.count {
                guard let item = itemsByID[filteredSaved[i]] else { continue }

                // Skip items that are currently temporarily shown.
                let tagString = "\(item.tag.namespace):\(item.tag.title)"
                guard !activelyShownTags.contains(tagString) else { continue }

                do {
                    try await move(item: item, to: .leftOfItem(currentAnchor), skipInputPause: true)
                    didMove = true
                    // Only advance the anchor after a successful move so that
                    // the next item targets the last correctly placed position.
                    currentAnchor = item
                } catch {
                    MenuBarItemManager.diagLog.error(
                        """
                        Failed to restore position for \(item.logString) in \
                        \(sectionKeyString): \(error)
                        """
                    )
                }
            }
        }

        return didMove
    }

    /// Returns the best-known bounds for a menu bar item.
    private func bestBounds(for item: MenuBarItem) -> CGRect {
        Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
    }

    /// Enforces the order of the given control items, ensuring that the
    /// control item for the always-hidden section is positioned to the
    /// left of control item for the hidden section.
    private func enforceControlItemOrder(controlItems: ControlItemPair) async {
        let hidden = controlItems.hidden

        guard
            let alwaysHidden = controlItems.alwaysHidden,
            hidden.bounds.maxX <= alwaysHidden.bounds.minX
        else {
            return
        }

        do {
            MenuBarItemManager.diagLog.debug("Control items have incorrect order")
            try await move(item: alwaysHidden, to: .leftOfItem(hidden), skipInputPause: true)
        } catch {
            MenuBarItemManager.diagLog.error("Error enforcing control item order: \(error)")
        }
    }

    /// Returns a Boolean value that indicates whether any menu bar item
    /// currently has a menu open.
    func isAnyMenuBarItemMenuOpen() async -> Bool {
        // Get all menu bar items that are currently on screen.
        let items = await MenuBarItem.getMenuBarItems(option: .onScreen)
        let sourcePIDs = Set(items.compactMap { $0.sourcePID })

        // Get all on-screen windows.
        let windows = WindowInfo.createWindows(option: .onScreen)

        MenuBarItemManager.diagLog.debug("Checking for open menus - Found \(items.count) menu bar items with PIDs: \(sourcePIDs)")

        // Check if any of the items' owning applications have a menu-related window.
        let result = windows.contains { window in
            // Skip Control Center windows as they can be falsely detected when hovering
            guard window.owningApplication?.bundleIdentifier != MenuBarItemTag.Namespace.controlCenter.description else {
                MenuBarItemManager.diagLog.debug("Skipping Control Center window: PID \(window.ownerPID), title: \(window.title ?? "nil")")
                return false
            }

            let isMenuOpen = sourcePIDs.contains(window.ownerPID) && window.isMenuRelated && (window.title?.isEmpty ?? true)
            if isMenuOpen {
                MenuBarItemManager.diagLog.debug("Found open menu window: PID \(window.ownerPID), owner: \(window.ownerName as NSObject?), title: \(window.title ?? "nil"), isMenuRelated: \(window.isMenuRelated)")
            }
            return isMenuOpen
        }

        MenuBarItemManager.diagLog.debug("Menu open check result: \(result)")
        return result
    }
}

// MARK: - MenuBarItemEventType

/// Event types for menu bar item events.
private enum MenuBarItemEventType {
    /// The event type for moving a menu bar item.
    case move(MoveSubtype)
    /// The event type for clicking a menu bar item.
    case click(ClickSubtype)

    var cgEventType: CGEventType {
        switch self {
        case let .move(subtype): subtype.cgEventType
        case let .click(subtype): subtype.cgEventType
        }
    }

    var cgEventFlags: CGEventFlags {
        switch self {
        case .move(.mouseDown): .maskCommand
        case .move, .click: []
        }
    }

    var cgMouseButton: CGMouseButton {
        switch self {
        case .move: .left
        case let .click(subtype): subtype.cgMouseButton
        }
    }

    // MARK: Subtypes

    /// Subtype for menu bar item move events.
    enum MoveSubtype {
        case mouseDown
        case mouseUp

        var cgEventType: CGEventType {
            switch self {
            case .mouseDown: .leftMouseDown
            case .mouseUp: .leftMouseUp
            }
        }
    }

    /// Subtype for menu bar item click events.
    enum ClickSubtype {
        case leftMouseDown
        case leftMouseUp
        case rightMouseDown
        case rightMouseUp
        case otherMouseDown
        case otherMouseUp

        var cgEventType: CGEventType {
            switch self {
            case .leftMouseDown: .leftMouseDown
            case .leftMouseUp: .leftMouseUp
            case .rightMouseDown: .rightMouseDown
            case .rightMouseUp: .rightMouseUp
            case .otherMouseDown: .otherMouseDown
            case .otherMouseUp: .otherMouseUp
            }
        }

        var cgMouseButton: CGMouseButton {
            switch self {
            case .leftMouseDown, .leftMouseUp: .left
            case .rightMouseDown, .rightMouseUp: .right
            case .otherMouseDown, .otherMouseUp: .center
            }
        }

        var clickState: Int64 {
            switch self {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: 1
            case .leftMouseUp, .rightMouseUp, .otherMouseUp: 0
            }
        }
    }
}

// MARK: Layout Reset

extension MenuBarItemManager {
    /// Errors that can occur during a layout reset.
    enum LayoutResetError: LocalizedError {
        case missingAppState
        case missingControlItems

        var errorDescription: String? {
            switch self {
            case .missingAppState:
                "Unable to access app state"
            case .missingControlItems:
                "Couldn't find section dividers in the menu bar"
            }
        }

        var recoverySuggestion: String? {
            "Make sure \(Constants.displayName) is running and try again."
        }
    }

    /// Resets menu bar layout data to a fresh-install state and moves all
    /// movable, hideable items (except the Thaw icon) to the
    /// Hidden section.
    ///
    /// - Returns: The number of items that failed to move.
    func resetLayoutToFreshState() async throws -> Int {
        MenuBarItemManager.diagLog.info("Resetting menu bar layout to fresh state")
        isResettingLayout = true
        defer { isResettingLayout = false }

        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        // Reset persisted state so macOS treats section dividers like new.
        ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue] = 0
        ControlItemDefaults.resetChevronPositions()

        // Forget previously seen/pinned items so we treat everything as new.
        knownItemIdentifiers.removeAll()
        pinnedHiddenBundleIDs.removeAll()
        pinnedAlwaysHiddenBundleIDs.removeAll()
        pendingRelocations.removeAll()
        pendingReturnDestinations.removeAll()
        savedSectionOrder.removeAll()
        persistKnownItemIdentifiers()
        persistPinnedBundleIDs()
        persistPendingRelocations()
        persistSavedSectionOrder()
        temporarilyShownItemContexts.removeAll()

        // Prevent the first post-reset cache pass from treating the freshly reset items as "new".
        suppressNextNewLeftmostItemRelocation = true

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        let hiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenWID
        ) else {
            MenuBarItemManager.diagLog.error("Layout reset aborted: missing hidden section control item")

            // Attempt a forced restore by re-enabling the always hidden section flag and
            // nudging macOS to recreate control items, then retry once.
            if appState.settings.advanced.enableAlwaysHiddenSection {
                appState.settings.advanced.enableAlwaysHiddenSection = false
                try? await Task.sleep(for: .milliseconds(50))
                appState.settings.advanced.enableAlwaysHiddenSection = true
                try? await Task.sleep(for: .milliseconds(150))

                items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                if let retryControlItems = ControlItemPair(
                    items: &items,
                    hiddenControlItemWindowID: hiddenWID,
                    alwaysHiddenControlItemWindowID: alwaysHiddenWID
                ) {
                    MenuBarItemManager.diagLog.info("Recovered hidden section control item after re-enabling always-hidden section")
                    return try await resetLayoutWithControlItems(controlItems: retryControlItems, items: items)
                }
            }

            throw LayoutResetError.missingControlItems
        }

        await enforceControlItemOrder(controlItems: controlItems)

        return try await resetLayoutWithControlItems(controlItems: controlItems, items: items)
    }

    private func resetLayoutWithControlItems(controlItems: ControlItemPair, items: [MenuBarItem]) async throws -> Int {
        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        func movePass(_ items: [MenuBarItem], anchor: MenuBarItem) async -> Int {
            var failed = 0
            for item in items {
                if item.tag == .visibleControlItem {
                    continue // Keep the Thaw icon in the visible section if enabled.
                }

                guard item.isMovable, item.canBeHidden, !item.isControlItem else {
                    continue
                }

                do {
                    try await move(
                        item: item,
                        to: .leftOfItem(anchor),
                        skipInputPause: true,
                        watchdogTimeout: Self.layoutWatchdogTimeout
                    )
                } catch {
                    failed += 1
                    MenuBarItemManager.diagLog.error("Failed to move \(item.logString) during layout reset: \(error)")
                }
            }
            return failed
        }

        _ = await movePass(items, anchor: controlItems.hidden)

        // Give macOS a moment to settle after the first pass.
        try? await Task.sleep(for: .milliseconds(200))

        // Re-fetch and retry only items that are NOT yet in the hidden
        // section. This covers items still in the visible section (to the
        // right of the hidden control item) as well as items stuck in the
        // always-hidden section (to the left of the always-hidden control
        // item) when that section is enabled.
        var refreshedItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedMoves = 0
        let refreshHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let refreshAlwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        if let refreshedControls = ControlItemPair(
            items: &refreshedItems,
            hiddenControlItemWindowID: refreshHiddenWID,
            alwaysHiddenControlItemWindowID: refreshAlwaysHiddenWID
        ) {
            let hiddenControlBounds = Bridging.getWindowBounds(for: refreshedControls.hidden.windowID)
                ?? refreshedControls.hidden.bounds
            let alwaysHiddenControlBounds = refreshedControls.alwaysHidden.flatMap {
                Bridging.getWindowBounds(for: $0.windowID) ?? $0.bounds
            }

            let notYetInHidden = refreshedItems.filter { item in
                guard item.isMovable, item.canBeHidden, !item.isControlItem,
                      item.tag != .visibleControlItem
                else {
                    return false
                }
                let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds

                // Still in the visible section (to the right of hidden control item).
                if bounds.minX >= hiddenControlBounds.maxX {
                    return true
                }
                // Still in the always-hidden section (to the left of always-hidden control item).
                if let ahBounds = alwaysHiddenControlBounds,
                   bounds.maxX <= ahBounds.minX
                {
                    return true
                }
                return false
            }
            if !notYetInHidden.isEmpty {
                MenuBarItemManager.diagLog.debug("Layout reset pass 2: \(notYetInHidden.count) items not yet in hidden section")
                failedMoves = await movePass(notYetInHidden, anchor: refreshedControls.hidden)
            }
        }

        await cacheActor.clearCachedItemWindowIDs()
        itemCache = ItemCache(displayID: nil)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.backgroundCacheContinuation = continuation
            Task { [weak self] in
                await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
        }
        suppressNextNewLeftmostItemRelocation = false

        await MainActor.run {
            appState.imageCache.clearAll()
            appState.imageCache.performCacheCleanup()
        }

        if itemCache.displayID != nil {
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        } else {
            try? await Task.sleep(for: .milliseconds(350))
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        }

        await MainActor.run {
            appState.objectWillChange.send()
        }

        return failedMoves
    }

    /// Wrapper for UI callers; kept separate for clarity in call sites.
    @MainActor
    func resetLayoutFromSettingsPane() async throws -> Int {
        try await resetLayoutToFreshState()
    }
}

// MARK: - CGEventField Helpers

private extension CGEventField {
    /// Key to access a field that contains the event's window identifier.
    static let windowID = CGEventField(rawValue: 0x33)! // swiftlint:disable:this force_unwrapping

    /// Fields that can be used to compare menu bar item events.
    static let menuBarItemEventFields: [CGEventField] = [
        .eventSourceUserData,
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
        .windowID,
    ]
}

// MARK: - CGEventFilterMask Helpers

private extension CGEventFilterMask {
    /// Specifies that all events should be permitted during event suppression states.
    static let permitAllEvents: CGEventFilterMask = [
        .permitLocalMouseEvents,
        .permitLocalKeyboardEvents,
        .permitSystemDefinedEvents,
    ]
}

// MARK: - CGEventType Helpers

private extension CGEventType {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .null: "null event"
        case .leftMouseDown: "leftMouseDown event"
        case .leftMouseUp: "leftMouseUp event"
        case .rightMouseDown: "rightMouseDown event"
        case .rightMouseUp: "rightMouseUp event"
        case .mouseMoved: "mouseMoved event"
        case .leftMouseDragged: "leftMouseDragged event"
        case .rightMouseDragged: "rightMouseDragged event"
        case .keyDown: "keyDown event"
        case .keyUp: "keyUp event"
        case .flagsChanged: "flagsChanged event"
        case .scrollWheel: "scrollWheel event"
        case .tabletPointer: "tabletPointer event"
        case .tabletProximity: "tabletProximity event"
        case .otherMouseDown: "otherMouseDown event"
        case .otherMouseUp: "otherMouseUp event"
        case .otherMouseDragged: "otherMouseDragged event"
        case .tapDisabledByTimeout: "tapDisabledByTimeout event"
        case .tapDisabledByUserInput: "tapDisabledByUserInput event"
        @unknown default: "unknown event"
        }
    }
}

// MARK: - CGMouseButton Helpers

private extension CGMouseButton {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .left: "left mouse button"
        case .right: "right mouse button"
        case .center: "center mouse button"
        @unknown default: "unknown mouse button"
        }
    }
}

// MARK: - Duration Helpers

private extension Duration {
    /// Returns the duration in milliseconds as a Double.
    var milliseconds: Double {
        let (seconds, attoseconds) = self.components
        return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }
    
}

// MARK: - CGEvent Helpers

private extension CGEvent {
    /// Returns an event that can be sent to a menu bar item.
    ///
    /// - Parameters:
    ///   - item: The event's target item.
    ///   - source: The event's source.
    ///   - type: The event's specialized type.
    ///   - location: The event's location. Does not need to be
    ///     within the bounds of the item.
    static func menuBarItemEvent(
        item: MenuBarItem,
        source: CGEventSource,
        type: MenuBarItemEventType,
        location: CGPoint
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type.cgEventType,
            mouseCursorPosition: location,
            mouseButton: type.cgMouseButton
        ) else {
            return nil
        }
        event.setFlags(for: type)
        event.setUserData(ObjectIdentifier(event))
        event.setWindowID(item.windowID, for: type)
        event.setClickState(for: type)
        return event
    }

    /// Returns a null event with unique user data.
    static func uniqueNullEvent() -> CGEvent? {
        guard let event = CGEvent(source: nil) else {
            return nil
        }
        event.setUserData(ObjectIdentifier(event))
        return event
    }

    /// Posts the event to the given event tap location.
    ///
    /// - Parameter location: The event tap location to post the event to.
    func post(to location: EventTap.Location) {
        let type = self.type
        MenuBarItemManager.diagLog.debug(
            """
            Posting \(type.logString) \
            to \(location.logString)
            """
        )
        switch location {
        case .hidEventTap: post(tap: .cghidEventTap)
        case .sessionEventTap: post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap: post(tap: .cgAnnotatedSessionEventTap)
        case let .pid(pid): postToPid(pid)
        }
    }

    /// Returns a Boolean value that indicates whether the given integer
    /// fields from this event are equivalent to the same integer fields
    /// from the specified event.
    ///
    /// - Parameters:
    ///   - other: The event to compare with this event.
    ///   - fields: The integer fields to check.
    func matches(_ other: CGEvent, byIntegerFields fields: [CGEventField]) -> Bool {
        fields.allSatisfy { field in
            getIntegerValueField(field) == other.getIntegerValueField(field)
        }
    }

    func setTargetPID(_ pid: pid_t) {
        let targetPID = Int64(pid)
        setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
    }

    private func setFlags(for type: MenuBarItemEventType) {
        flags = type.cgEventFlags
    }

    private func setUserData(_ bitPattern: ObjectIdentifier) {
        let userData = Int64(Int(bitPattern: bitPattern))
        setIntegerValueField(.eventSourceUserData, value: userData)
    }

    private func setWindowID(_ windowID: CGWindowID, for type: MenuBarItemEventType) {
        let windowID = Int64(windowID)

        setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
        setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)

        if case .move = type {
            setIntegerValueField(.windowID, value: windowID)
        }
    }

    private func setClickState(for type: MenuBarItemEventType) {
        if case let .click(subtype) = type {
            setIntegerValueField(.mouseEventClickState, value: subtype.clickState)
        }
    }
}
