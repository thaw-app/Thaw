//
//  MenuBarItemManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
@preconcurrency import Combine
@preconcurrency import CoreGraphics
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
            // The waiter was already consumed by signal(); don't touch the value.
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
    ///
    /// Standard counting-semaphore semantics: always increment value,
    /// then wake a queued waiter only when the post-increment value is
    /// still non-positive (meaning waiters remain). The previous
    /// implementation skipped the increment when waking a waiter, which
    /// caused value to drift negative when concurrent callers queued
    /// up during a long-running holder; every subsequent caller would
    /// then see value < 0 in wait and suspend forever even after all
    /// prior holders had released.
    func signal() {
        value += 1
        if value <= 0, let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume(returning: ())
        }
    }

    /// Resets the semaphore to a given value, cancelling all pending waiters.
    /// Use ONLY as a last resort when the semaphore is suspected to be leaked.
    func reset(to value: Int = 1) {
        for waiter in waiters {
            waiter.continuation.resume(throwing: CancellationError())
        }
        waiters.removeAll()
        self.value = value
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
    private nonisolated(unsafe) var rehideTimer: Timer?
    private nonisolated(unsafe) var rehideCancellable: AnyCancellable?

    /// Timestamp of the most recent menu bar item move operation.
    private var lastMoveOperationTimestamp: ContinuousClock.Instant?

    /// Cached timeouts for move operations.
    private var moveOperationTimeouts = [MenuBarItemTag: Duration]()

    /// Cached timeouts for click operations (adaptive per app).
    private var clickOperationTimeouts = [MenuBarItemTag: Duration]()
    /// Serialization gate for cache operations.
    private let cacheGate = CacheGate()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The currently running "is any menu open" probe, reused so concurrent
    /// smart-rehide callers do not all trigger their own full menu-bar scan.
    private var menuOpenCheckTask: Task<Bool, Never>?

    /// The most recent open-menu probe result and its timestamp.
    private var menuOpenCheckCachedResult: Bool?
    private var menuOpenCheckCachedAt: ContinuousClock.Instant?

    /// Timer for lightweight periodic cache checks.
    private nonisolated(unsafe) var cacheTickCancellable: AnyCancellable?

    /// Persisted identifiers of menu bar items we've already seen.
    private var knownItemIdentifiers = Set<String>()
    /// Suppresses the next automatic relocation of newly seen leftmost items.
    private var suppressNextNewLeftmostItemRelocation = false

    deinit {
        rehideTimer?.invalidate()
        rehideCancellable?.cancel()
        cacheTickCancellable?.cancel()
        menuOpenCheckTask?.cancel()
    }

    /// Continuation to signal when background cache task completes.
    private var backgroundCacheContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Layout coordination state
    //
    // The flags below coordinate three overlapping concerns. They are
    // not collapsed into a single token because the AX-timing and live-
    // Window-Server interactions each one guards have evolved
    // independently from production incidents. Any consolidation needs
    // manual smoke-testing on real hardware to catch regressions that
    // unit tests cannot.
    //
    // 1. In-flight gating of the cache cycle. While one of these is
    //    set, cacheItemsRegardless suppresses restore, late-arrival
    //    detection, or section-order saves so an in-flight operation
    //    isn't fought by the cycle:
    //      - isResettingLayout
    //      - isRestoringItemOrder (+ isRestoringItemOrderTimestamp)
    //      - isApplyingProfileLayout
    //      - suppressNextNewLeftmostItemRelocation
    //
    // 2. Startup settling. Gates restore and saves during the cold-boot
    //    or post-permission-grant window when many apps appear at once:
    //      - isInStartupSettling (+ startupSettlingTask)
    //      - settlingDeadline
    //      - settlingExpectedBundleIDs
    //      - settlingKind
    //
    // 3. Active-profile re-sort. Caches the last-applied profile spec so
    //    a late-arriving profile item can be reinserted without a full
    //    re-apply:
    //      - activeProfileLayout
    //      - activeProfileItemIdentifiers
    //      - profileSortedItemIdentifiers
    //      - profileResortTask
    //
    // isApplyingProfileLayout sits in both group 1 and group 3 because
    // it both gates the cache cycle and marks an active profile apply
    // window for the re-sort path.

    /// Suppresses image cache updates during layout reset to prevent stale cache during moves.
    var isResettingLayout = false
    /// Suppresses saving section order during an active order-restore pass.
    private var isRestoringItemOrder = false
    /// Timestamp when isRestoringItemOrder was set (for timeout detection).
    private var isRestoringItemOrderTimestamp: Date?
    /// True during the startup settling period, during which restore operations
    /// and section-order saves are suppressed. This prevents cascading icon moves
    /// when many apps launch at login (login item boot) or restart in quick succession
    /// (e.g. app update checks). Cleared after a fixed delay, then one final
    /// restore runs to enforce the user's saved layout.
    private var isInStartupSettling = false
    /// Handle to the in-flight startup settling Task. Retained so that a
    /// subsequent performSetup() call can cancel the previous settling period
    /// before starting a new one, preventing multiple concurrent settling tasks.
    private var startupSettlingTask: Task<Void, Never>?
    /// Handle to the initial cache warm-up task. The first full cache can be
    /// expensive on dense menu bars, so it runs off the startup critical path.
    private var initialCacheTask: Task<Void, Never>?
    /// Absolute deadline for the current startup settling period. Stored so
    /// that a re-entry of performSetup() (e.g. permission re-grant) can
    /// preserve any remaining time from the original period rather than
    /// resetting to a shorter delay based on current systemUptime.
    private var settlingDeadline: ContinuousClock.Instant?
    /// Bundle IDs the current settling period is waiting on. Empty for a
    /// preflight (count-stability) settling. Promoted to non-empty when
    /// startSettlingPeriod is called with expectedBundleIDs after a real
    /// relaunch wave; cancelSettlingPeriod refuses to tear down a promoted
    /// settling so a concurrent no-op apply cannot clobber an in-flight
    /// wait for relaunched apps to reattach.
    private var settlingExpectedBundleIDs = Set<String>()

    /// Authority class of the current settling period. Used so that a
    /// less-authoritative preflight cannot tear down or replace a
    /// more-authoritative settling already in flight.
    ///
    /// - cold: started by performSetup; the cold-boot wait while menu
    ///   bar items are still loading. Cannot be cancelled or replaced
    ///   by a preflight, only by another cold (re-entry) or a real
    ///   expected-set relaunch.
    /// - preflight: started before applyOffset to suppress restore
    ///   while the wave runs. Cancellable by the matching no-op path.
    /// - expectedSet: post-relaunch wave waiting on specific bundle IDs
    ///   to reattach. Cancellation is already gated by the non-empty
    ///   settlingExpectedBundleIDs; tracked here for parity.
    private enum SettlingKind {
        case cold
        case preflight
        case expectedSet
    }

    private var settlingKind: SettlingKind?
    /// Persisted bundle identifiers explicitly placed in hidden section.
    private var pinnedHiddenBundleIDs = Set<String>()
    /// Persisted bundle identifiers explicitly placed in always-hidden section.
    private var pinnedAlwaysHiddenBundleIDs = Set<String>()

    /// Cached layout parameters from the last profile apply, used to re-sort
    /// when profile-listed items appear after the initial apply.
    private var activeProfileLayout: (
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    )?

    /// Flattened set of item identifiers from the active profile's itemOrder,
    /// for O(1) lookup when detecting late-arriving profile items.
    private var activeProfileItemIdentifiers = Set<String>()

    /// Set of item identifiers that were present when the profile layout was
    /// last applied (or re-applied). Used to detect genuinely new arrivals.
    private var profileSortedItemIdentifiers = Set<String>()

    /// Handle for the debounced profile re-sort task. Cancelled and re-created
    /// each time a new late-arriving profile item is detected.
    private var profileResortTask: Task<Void, Never>?

    /// True while `applyProfileLayout` is executing. Suppresses the
    /// late-arrival detection in `cacheItemsRegardless` to prevent
    /// false re-sort triggers during an in-flight sort.
    private var isApplyingProfileLayout = false

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
    /// Placement preference for newly detected menu bar items.
    @Published private(set) var newItemsPlacement = NewItemsPlacement.defaultValue

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

    struct NewItemsPlacement: Codable, Equatable {
        enum Relation: String, Codable {
            case leftOfAnchor
            case rightOfAnchor
            case sectionDefault
        }

        let sectionKey: String
        let anchorIdentifier: String?
        let relation: Relation

        static let defaultValue = NewItemsPlacement(
            sectionKey: Defaults.DefaultValue.newItemsSection,
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
    }

    /// Loads the persisted placement preference for newly detected menu bar items.
    private func loadNewItemsPlacementPreference() {
        if let data = Defaults.data(forKey: .newItemsPlacementData),
           let stored = try? JSONDecoder().decode(NewItemsPlacement.self, from: data)
        {
            newItemsPlacement = stored
            return
        }

        let storedSection = Defaults.string(forKey: .newItemsSection) ?? Defaults.DefaultValue.newItemsSection
        let resolvedSection = sectionName(for: storedSection) ?? .hidden
        newItemsPlacement = NewItemsPlacement(
            sectionKey: sectionKey(for: resolvedSection),
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
    }

    /// Persists the placement preference for newly detected menu bar items.
    private func persistNewItemsPlacementPreference() {
        Defaults.set(newItemsPlacement.sectionKey, forKey: .newItemsSection)
        if let data = try? JSONEncoder().encode(newItemsPlacement) {
            Defaults.set(data, forKey: .newItemsPlacementData)
        } else {
            Defaults.removeObject(forKey: .newItemsPlacementData)
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
    /// Computes the per-section item order dict from the given cache
    /// using the same filter and closed-app preservation logic that
    /// saveSectionOrder applies before persisting. Returns the dict
    /// without writing it anywhere.
    ///
    /// Exposed (rather than inlined inside saveSectionOrder) so the
    /// profile-capture path in ProfileManager.captureCurrentLayout can
    /// build its itemOrder field through the same pipeline. Without a
    /// shared helper, itemOrder was a raw itemCache snapshot that
    /// drifted from savedSectionOrder: it excluded closed-app entries
    /// that savedSectionOrder preserves through planSectionOrder's
    /// merge, and it included transient Control Center items
    /// (Live Activities, iPhone Mirroring) that savedSectionOrder
    /// filters out. On profile re-apply that drift caused
    /// closed-but-saved apps (e.g. jetbrains while the app is quit) to
    /// be treated as unmanaged and routed through planUnmanagedPlacement
    /// instead of landing at their saved section.
    ///
    /// Filter and merge:
    ///   - control items are excluded except the visibleControlItem
    ///     (Thaw chevron); its position within the visible section is
    ///     persisted so the LCS planner can detect when macOS placed
    ///     an app item on the wrong side of the chevron;
    ///   - non-control items without a resolved sourcePID are
    ///     excluded (their UIDs are unstable and would churn entries
    ///     every cycle);
    ///   - transient Control Center items (Live Activities, iPhone
    ///     Mirroring, generic Apple Item-0 placeholders) are excluded
    ///     so their ephemeral identifiers never enter the dict;
    ///   - items whose true section is recorded in
    ///     pendingReturnDestinations / pendingRelocations are treated
    ///     as closed-apps (preserves their pre-temporarilyShow section
    ///     instead of capturing the live visible position);
    ///   - LayoutSolver.planSectionOrder merges currentInSection with
    ///     closed-app entries from the previous savedSectionOrder so an
    ///     app's slot survives a quit / restart cycle.
    func computeSectionOrder(from cache: ItemCache) -> [String: [String]] {
        var newOrder = [String: [String]]()

        let pendingRehideTagIDs = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: pendingReturnDestinations,
            pendingRelocations: pendingRelocations,
            waitForRelaunchPrefix: Self.waitForRelaunchPrefix
        )

        // Predicate: items eligible for persistence in savedSectionOrder.
        // Profile-tracked app items (non-control with resolved sourcePID)
        // are the typical case. The visibleControlItem (Thaw chevron) is
        // also persisted so its user-chosen position within the visible
        // section survives Thaw restarts: without it, savedSectionOrder
        // describes profile-item order but not where the chevron sits
        // relative to them, and on restart the LCS planner can't detect
        // when macOS placed an app item on the wrong side of the chevron.
        // The hidden / alwaysHidden control items stay excluded; they
        // are section dividers whose position is implicit (always at the
        // section boundary) and they get inserted into desiredFlat at
        // the boundary regardless of saved order.
        func isPersistable(_ item: MenuBarItem) -> Bool {
            if item.tag == .visibleControlItem {
                return true
            }
            return !item.isControlItem && item.sourcePID != nil
        }

        var allCurrentIdentifiers = Set<String>()
        var allCurrentBaseIdentifiers = Set<String>()
        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where isPersistable(item) {
                guard !pendingRehideTagIDs.contains(item.tag.tagIdentifier) else { continue }
                // Always track base identifier so stale saved entries for
                // transient items (Live Activities) get pruned by the
                // isStaleInstanceIndex guard below and not re-injected.
                let baseID = "\(item.tag.namespace):\(item.tag.title)"
                allCurrentBaseIdentifiers.insert(baseID)
                // Exclude transient Control Center items (Live Activities,
                // iPhone Mirroring icons) from the identifier set so their
                // ephemeral UIDs are never written to savedSectionOrder.
                guard !item.isTransientControlCenterItem else { continue }
                allCurrentIdentifiers.insert(item.uniqueIdentifier)
            }
        }

        for section in MenuBarSection.Name.allCases {
            // Current identifiers for this section, in cache iteration
            // order (which approximates left-to-right X order).
            let currentInSection = cache[section]
                .filter {
                    isPersistable($0) &&
                        !$0.isTransientControlCenterItem &&
                        !pendingRehideTagIDs.contains($0.tag.tagIdentifier)
                }
                .map(\.uniqueIdentifier)

            let oldSavedForSection = savedSectionOrder[sectionKey(for: section)] ?? []

            // Delegate to planSectionOrder for the position-preserving
            // merge of current items with closed-app entries. This
            // replaces the old "append closed apps to the end" logic
            // that destroyed user-intended positions on every quit.
            let identifiers = LayoutSolver.planSectionOrder(
                currentInSection: currentInSection,
                oldSavedForSection: oldSavedForSection,
                allCurrentIdentifiers: allCurrentIdentifiers,
                allCurrentBaseIdentifiers: allCurrentBaseIdentifiers
            )

            if !identifiers.isEmpty {
                newOrder[sectionKey(for: section)] = identifiers
            }
        }

        return newOrder
    }

    /// Extracts the current per-section item order from the given cache
    /// and persists it to savedSectionOrder. Skips the write when the
    /// order has not changed. Delegates the dict construction to
    /// computeSectionOrder so the "what does the curated section order
    /// look like?" question has a single answer used by both periodic
    /// save and profile capture.
    private func saveSectionOrder(from cache: ItemCache) {
        let newOrder = computeSectionOrder(from: cache)
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

    /// Prefix used in `pendingRelocations` values to mark items whose rehide
    /// failed terminally in the current session. The suffix is the item's
    /// `windowID` at the time of failure, used to detect app relaunches.
    private static let waitForRelaunchPrefix = "waitForRelaunch:"

    /// Returns a `pendingRelocations` sentinel value that suppresses same-session
    /// move attempts. Encodes `windowID` so that a relaunch (new windowID) clears
    /// the suppression automatically.
    private func waitForRelaunchValue(windowID: CGWindowID, section: MenuBarSection.Name) -> String {
        "\(Self.waitForRelaunchPrefix)\(windowID):\(sectionKey(for: section))"
    }

    /// Parses a `pendingRelocations` sentinel value.
    /// Returns `(windowID, section)` if the value is a wait-for-relaunch entry,
    /// or `nil` if it is a plain section key.
    private func parseWaitForRelaunch(_ value: String) -> (windowID: CGWindowID, section: MenuBarSection.Name)? {
        guard value.hasPrefix(Self.waitForRelaunchPrefix) else { return nil }
        let payload = value.dropFirst(Self.waitForRelaunchPrefix.count)
        // Format: "<windowID>:<sectionKey>"
        guard let colonIndex = payload.firstIndex(of: ":") else { return nil }
        let widString = String(payload[payload.startIndex ..< colonIndex])
        let secString = String(payload[payload.index(after: colonIndex)...])
        guard let wid = CGWindowID(widString),
              let section = sectionName(for: secString)
        else { return nil }
        return (wid, section)
    }

    /// Returns the effective section for newly detected menu bar items, falling back
    /// to hidden when the always-hidden section is currently disabled.
    var effectiveNewItemsSection: MenuBarSection.Name {
        let preferredSection = sectionName(for: newItemsPlacement.sectionKey) ?? .hidden
        if preferredSection == .alwaysHidden, appState?.settings.advanced.enableAlwaysHiddenSection != true {
            return .hidden
        }
        return preferredSection
    }

    /// Returns the insertion index for the New Items badge within the given section.
    func newItemsBadgeIndex(in section: MenuBarSection.Name, itemIdentifiers: [String]) -> Int? {
        guard effectiveNewItemsSection == section else {
            return nil
        }

        if sectionName(for: newItemsPlacement.sectionKey) == section,
           let anchorIdentifier = newItemsPlacement.anchorIdentifier,
           let anchorIndex = resolvedNewItemsAnchorIndex(
               for: anchorIdentifier,
               in: itemIdentifiers
           )
        {
            switch newItemsPlacement.relation {
            case .leftOfAnchor:
                return anchorIndex
            case .rightOfAnchor:
                return anchorIndex + 1
            case .sectionDefault:
                break
            }
        }

        // Anchor missing from this section (e.g. the notch-overflow
        // relocated the anchor item to hidden). Walk the active
        // profile's saved order outward from the missing anchor's
        // saved position to find its nearest sibling that IS still
        // present in this section, and place the badge against that
        // sibling. This preserves the badge's saved relative position
        // when its primary anchor is unavailable, instead of dropping
        // it to the section's default index.
        if let nearestIndex = badgeIndexFromNearestProfileSibling(
            in: section,
            itemIdentifiers: itemIdentifiers
        ) {
            return nearestIndex
        }

        return defaultNewItemsBadgeIndex(in: section, itemCount: itemIdentifiers.count)
    }

    /// Walks the active profile's saved item order outward from the
    /// badge's missing anchor and returns an insertion index against
    /// the first sibling that's still present in `itemIdentifiers`.
    /// Walks in the direction implied by the saved relation first
    /// (leftOfAnchor → walk left toward earlier siblings; rightOfAnchor
    /// → walk right toward later siblings), then the opposite direction
    /// if the first walk doesn't find a survivor. Returns nil when no
    /// active profile is loaded, no profile order exists for this
    /// section, or no sibling survives.
    private func badgeIndexFromNearestProfileSibling(
        in section: MenuBarSection.Name,
        itemIdentifiers: [String]
    ) -> Int? {
        guard let anchorIdentifier = newItemsPlacement.anchorIdentifier,
              newItemsPlacement.relation != .sectionDefault,
              sectionName(for: newItemsPlacement.sectionKey) == section,
              let profileOrder = activeProfileLayout?.itemOrder[sectionKey(for: section)],
              let anchorPos = profileOrder.firstIndex(of: anchorIdentifier)
        else {
            return nil
        }
        let walkLeftFirst = newItemsPlacement.relation == .leftOfAnchor
        // First pass: walk in the direction the badge was relative to
        // the anchor. If badge was leftOfAnchor, the badge sat between
        // some left-side sibling and the anchor; finding that left
        // sibling and placing rightOfThatSibling reproduces the saved
        // position. Symmetric for rightOfAnchor.
        if walkLeftFirst {
            for i in stride(from: anchorPos - 1, through: 0, by: -1) {
                if let idx = itemIdentifiers.firstIndex(of: profileOrder[i]) {
                    return idx + 1
                }
            }
            for i in (anchorPos + 1) ..< profileOrder.count {
                if let idx = itemIdentifiers.firstIndex(of: profileOrder[i]) {
                    return idx
                }
            }
        } else {
            for i in (anchorPos + 1) ..< profileOrder.count {
                if let idx = itemIdentifiers.firstIndex(of: profileOrder[i]) {
                    return idx
                }
            }
            for i in stride(from: anchorPos - 1, through: 0, by: -1) {
                if let idx = itemIdentifiers.firstIndex(of: profileOrder[i]) {
                    return idx + 1
                }
            }
        }
        return nil
    }

    /// Updates the preferred destination for newly detected menu bar items using the
    /// badge position from the layout editor.
    func updateNewItemsPlacement(
        section: MenuBarSection.Name,
        arrangedViews: [LayoutBarArrangedView]
    ) {
        let resolvedSection: MenuBarSection.Name = if section == .alwaysHidden, appState?.settings.advanced.enableAlwaysHiddenSection != true {
            .hidden
        } else {
            section
        }

        let updatedPlacement: NewItemsPlacement
        if let badgeIndex = arrangedViews.firstIndex(where: { $0.isNewItemsBadge }) {
            let rightNeighbor = arrangedViews[(badgeIndex + 1) ..< arrangedViews.count]
                .compactMap { view -> MenuBarItem? in
                    if case let .item(item) = view.kind { return item }
                    return nil
                }
                .first

            let leftNeighbor = arrangedViews[..<badgeIndex]
                .reversed()
                .compactMap { view -> MenuBarItem? in
                    if case let .item(item) = view.kind { return item }
                    return nil
                }
                .first

            if let rightNeighbor {
                updatedPlacement = NewItemsPlacement(
                    sectionKey: sectionKey(for: resolvedSection),
                    anchorIdentifier: persistedNewItemsAnchorIdentifier(for: rightNeighbor),
                    relation: .leftOfAnchor
                )
            } else if let leftNeighbor {
                updatedPlacement = NewItemsPlacement(
                    sectionKey: sectionKey(for: resolvedSection),
                    anchorIdentifier: persistedNewItemsAnchorIdentifier(for: leftNeighbor),
                    relation: .rightOfAnchor
                )
            } else {
                updatedPlacement = NewItemsPlacement(
                    sectionKey: sectionKey(for: resolvedSection),
                    anchorIdentifier: nil,
                    relation: .sectionDefault
                )
            }
        } else {
            updatedPlacement = NewItemsPlacement(
                sectionKey: sectionKey(for: resolvedSection),
                anchorIdentifier: nil,
                relation: .sectionDefault
            )
        }

        guard newItemsPlacement != updatedPlacement else {
            return
        }

        newItemsPlacement = updatedPlacement
        persistNewItemsPlacementPreference()
        MenuBarItemManager.diagLog.debug("Updated new item destination to \(resolvedSection.logString) at relation \(updatedPlacement.relation.rawValue)")
    }

    /// Applies a previously captured ``NewItemsPlacement`` (from a profile),
    /// clamping to the hidden section when the always-hidden section is
    /// disabled. Persists the updated preference.
    ///
    /// When clamping from `alwaysHidden` to `hidden`, the original anchor
    /// references an alwaysHidden item that won't resolve in the hidden
    /// section. Rather than letting the badge fall through to the
    /// `.hidden`/always-hidden-disabled default (which is the leftmost
    /// slot, farthest from the clock), we re-anchor to the rightmost
    /// existing hidden item with `.leftOfAnchor` so the badge lands on
    /// the clock-side edge of the section; the spot users reach first
    /// when they expand the hidden section.
    func applyNewItemsPlacement(_ placement: NewItemsPlacement) {
        let preferredSection = sectionName(for: placement.sectionKey) ?? .hidden
        let alwaysHiddenDisabled = appState?.settings.advanced.enableAlwaysHiddenSection != true
        let clampedToHidden = preferredSection == .alwaysHidden && alwaysHiddenDisabled
        let resolvedSection: MenuBarSection.Name = clampedToHidden ? .hidden : preferredSection

        let adjusted = if clampedToHidden {
            if let rightmostHiddenItem = itemCache[.hidden].first(
                where: { !$0.isControlItem && $0.tag.instanceIndex == 0 }
            ) {
                NewItemsPlacement(
                    sectionKey: sectionKey(for: resolvedSection),
                    anchorIdentifier: persistedNewItemsAnchorIdentifier(for: rightmostHiddenItem),
                    relation: .leftOfAnchor
                )
            } else {
                // Clamping, but the hidden section is empty. Drop the
                // stale alwaysHidden anchor and fall back to the section
                // default so a later re-save doesn't resurface it.
                NewItemsPlacement(
                    sectionKey: sectionKey(for: resolvedSection),
                    anchorIdentifier: nil,
                    relation: .sectionDefault
                )
            }
        } else {
            NewItemsPlacement(
                sectionKey: sectionKey(for: resolvedSection),
                anchorIdentifier: placement.anchorIdentifier,
                relation: placement.relation
            )
        }

        guard newItemsPlacement != adjusted else { return }

        newItemsPlacement = adjusted
        persistNewItemsPlacementPreference()
        MenuBarItemManager.diagLog.debug("Applied profile new item destination to \(resolvedSection.logString) at relation \(adjusted.relation.rawValue)")
    }

    /// Returns the move destination that inserts a new item into the preferred section.
    private func newItemsMoveDestination(
        for controlItems: ControlItemPair,
        among items: [MenuBarItem]
    ) -> MoveDestination {
        let targetSection = effectiveNewItemsSection
        var context = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )
        let activelyShownTags = Set(temporarilyShownItemContexts.map(\.tag.tagIdentifier))
        let liveSectionItems = items.filter { item in
            guard !item.isControlItem else { return false }
            guard !activelyShownTags.contains(item.tag.tagIdentifier) else { return false }
            return context.findSection(for: item) == targetSection
        }

        if sectionName(for: newItemsPlacement.sectionKey) == targetSection,
           let anchorIdentifier = newItemsPlacement.anchorIdentifier,
           let anchorItem = resolvedNewItemsAnchorItem(
               for: anchorIdentifier,
               in: liveSectionItems
           )
        {
            switch newItemsPlacement.relation {
            case .leftOfAnchor:
                return .leftOfItem(anchorItem)
            case .rightOfAnchor:
                return .rightOfItem(anchorItem)
            case .sectionDefault:
                break
            }
        }

        switch targetSection {
        case .visible:
            return .rightOfItem(controlItems.hidden)
        case .hidden:
            if appState?.settings.advanced.enableAlwaysHiddenSection == true {
                if let alwaysHidden = controlItems.alwaysHidden {
                    return .rightOfItem(alwaysHidden)
                } else {
                    return .leftOfItem(controlItems.hidden)
                }
            } else {
                return .leftOfItem(controlItems.hidden)
            }
        case .alwaysHidden:
            if let alwaysHidden = controlItems.alwaysHidden {
                return .leftOfItem(alwaysHidden)
            } else {
                return .leftOfItem(controlItems.hidden)
            }
        }
    }

    private func persistedNewItemsAnchorIdentifier(for item: MenuBarItem) -> String {
        item.uniqueIdentifier
    }

    private func resolvedNewItemsAnchorIndex(
        for anchorIdentifier: String,
        in itemIdentifiers: [String]
    ) -> Int? {
        if let exactMatch = itemIdentifiers.firstIndex(of: anchorIdentifier) {
            return exactMatch
        }

        let stableIdentifier = stableNewItemsAnchorIdentifier(from: anchorIdentifier)

        return itemIdentifiers.firstIndex { identifier in
            stableNewItemsAnchorIdentifier(from: identifier) == stableIdentifier
        }
    }

    private func resolvedNewItemsAnchorItem(
        for anchorIdentifier: String,
        in items: [MenuBarItem]
    ) -> MenuBarItem? {
        if let exactMatch = items.first(where: { $0.uniqueIdentifier == anchorIdentifier }) {
            return exactMatch
        }

        let stableIdentifier = stableNewItemsAnchorIdentifier(from: anchorIdentifier)

        return items.first { item in
            persistedNewItemsAnchorIdentifier(for: item) == stableIdentifier
        }
    }

    private func stableNewItemsAnchorIdentifier(from identifier: String) -> String {
        identifier
    }

    private func defaultNewItemsBadgeIndex(in section: MenuBarSection.Name, itemCount: Int) -> Int {
        switch section {
        case .visible:
            return 0
        case .hidden:
            if appState?.settings.advanced.enableAlwaysHiddenSection == true {
                return 0
            }
            return itemCount
        case .alwaysHidden:
            return itemCount
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
        loadNewItemsPlacementPreference()
        MenuBarItemManager.diagLog.debug("performSetup: loaded \(knownItemIdentifiers.count) known identifiers, \(pinnedHiddenBundleIDs.count) pinned hidden, \(pinnedAlwaysHiddenBundleIDs.count) pinned always-hidden, \(savedSectionOrder.values.map(\.count)) saved order entries")
        // On first launch (no known identifiers), avoid auto-relocating the leftmost item
        // so everything remains in the hidden section until the user interacts.
        suppressNextNewLeftmostItemRelocation = knownItemIdentifiers.isEmpty
        configureCancellables(with: appState)
        initialCacheTask?.cancel()
        MenuBarItemManager.diagLog.debug("performSetup: scheduling initial cacheItemsRegardless off the startup critical path")
        self.initialCacheTask = Task { @MainActor [weak self] in
            guard let self else { return }
            MenuBarItemManager.diagLog.debug(
                "performSetup: initial cacheItemsRegardless started (fast path without sourcePID resolution)"
            )
            for attempt in 1 ... 10 {
                if Task.isCancelled {
                    return
                }
                await cacheItemsRegardless(resolveSourcePID: false)
                if itemCache.displayID != nil {
                    if attempt > 1 {
                        MenuBarItemManager.diagLog.debug(
                            "performSetup: fast initial cache succeeded on retry \(attempt)"
                        )
                    }
                    // Fast path succeeded; kick off authoritative PID resolution
                    // concurrently so we don't block restore logic.
                    Task { @MainActor [weak self] in
                        await self?.cacheItemsRegardless(resolveSourcePID: true)
                    }
                    break
                }

                MenuBarItemManager.diagLog.debug(
                    "performSetup: fast initial cache missing control items on attempt \(attempt), retrying shortly"
                )
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
            MenuBarItemManager.diagLog.debug("performSetup: initial cache complete, items in cache: visible=\(itemCache[.visible].count), hidden=\(itemCache[.hidden].count), alwaysHidden=\(itemCache[.alwaysHidden].count), managedItems=\(itemCache.managedItems.count)")
        }
        // Suppress restore and section-order saves for a settling period after launch.
        // During login (system uptime < 60 s) many apps load over ~30 s, each triggering
        // a cache cycle; without this guard every launch notification causes a restore
        // that conflicts with the next, producing the "icon parade" effect.
        // After the settling period ends, one final cacheItemsRegardless() enforces the
        // user's saved layout against whatever macOS placed items.
        startSettlingPeriod(reason: "performSetup")
        MenuBarItemManager.diagLog.debug("performSetup: MenuBarItemManager setup complete")
    }

    /// Starts a settling period during which restore and section-order saves
    /// are suppressed. The settling task polls cacheItemsRegardless until
    /// the menu bar has stabilized; then runs two final cache passes that
    /// trigger the saved-layout restore.
    ///
    /// Exit conditions, in priority order:
    /// 1. If expectedBundleIDs is non-empty: exit when all expected bundle
    ///    IDs are present in the cache AND sourcePIDs have resolved (≤1 nil).
    ///    This is the post-relaunch-wave case where we know exactly which
    ///    apps we're waiting on.
    /// 2. Otherwise: exit when the managed-item count has been stable for
    ///    stableTarget consecutive polls AND sourcePIDs have resolved.
    ///    This is the cold-start case where we don't know the expected set.
    /// 3. Hard upper bound is maxDuration from now. Sized generously
    ///    because some apps can take tens of seconds between process
    ///    respawn and menu bar item reattachment; the early-exit in (1)
    ///    or (2) ends settling immediately once the cache has caught up,
    ///    so the cap only matters when an app is genuinely slow or dead.
    ///
    /// On re-entry (e.g. a permission re-grant during login, or a relaunch
    /// wave fired by MenuBarItemSpacingManager): take the MAX of the
    /// previous deadline and the newly computed one so a second call does
    /// not silently truncate an in-flight window.
    func startSettlingPeriod(
        reason: String,
        expectedBundleIDs: Set<String> = [],
        maxDuration: Duration = .seconds(60)
    ) {
        // Classify the incoming call so we can refuse to demote a more
        // authoritative settling that's already in flight.
        let mergedExpected = settlingExpectedBundleIDs.union(expectedBundleIDs)
        let incomingKind: SettlingKind = if !mergedExpected.isEmpty {
            .expectedSet
        } else if reason == "performSetup" {
            .cold
        } else {
            .preflight
        }

        // Boot race: a cold (performSetup) or expected-set settling must
        // not be torn down by a transient preflight that the boot path
        // also kicks off (DisplaySettingsManager.applyActiveDisplaySpacing,
        // ProfileManager.layoutTask). Preserve the merged expected set so
        // a later non-preflight call still has it; otherwise return.
        if let existing = settlingKind,
           incomingKind == .preflight,
           existing == .cold || existing == .expectedSet
        {
            settlingExpectedBundleIDs = mergedExpected
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling start ignored; \(existing) settling already in flight"
            )
            return
        }

        let newMaxDeadline = ContinuousClock.now.advanced(by: maxDuration)
        let maxDeadline = max(settlingDeadline ?? newMaxDeadline, newMaxDeadline)
        settlingDeadline = maxDeadline
        settlingExpectedBundleIDs = mergedExpected
        settlingKind = incomingKind
        // Cancel any in-flight settling task before starting a new one.
        // The cancelled task exits without touching shared state; this call
        // manages isInStartupSettling for the new period.
        startupSettlingTask?.cancel()
        isInStartupSettling = true
        MenuBarItemManager.diagLog.debug("\(reason): settling period started (max duration: \(maxDuration))")
        // @MainActor ensures the flag flip and final cache call are never
        // interleaved with notification-triggered cache cycles between them.
        startupSettlingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // No-op when initialCacheTask is nil (i.e. settling started
            // outside performSetup, e.g. after a relaunch wave).
            await self.initialCacheTask?.value

            // --- Hybrid signal + timer settling ---
            // Two exit modes (besides the deadline backstop):
            // - "expected-set" mode (post-relaunch-wave): we know exactly
            //   which bundle IDs we just relaunched, so we wait for all of
            //   them to appear in the cache before declaring settled. Much
            //   tighter than the count-stability heuristic; once slow
            //   apps have all reattached, we exit immediately regardless
            //   of timer.
            // - "count-stability" mode (cold start, no expected set): poll
            //   until the managed-item count has been stable for several
            //   consecutive polls AND sourcePIDs have resolved.
            // Hard upper bound is maxDeadline (computed above), so an
            // app that never reattaches (process truly dead) doesn't
            // strand the layout pass.
            let stableTarget = 3
            var lastSeenCount = -1
            var stablePolls = 0
            let waitingFor = mergedExpected
            let useExpectedSet = !waitingFor.isEmpty
            if useExpectedSet {
                MenuBarItemManager.diagLog.debug(
                    "\(reason): waiting for \(waitingFor.count) expected bundle ID(s) to reattach"
                )
            }

            while !Task.isCancelled {
                if ContinuousClock.now > maxDeadline {
                    MenuBarItemManager.diagLog.debug(
                        "\(reason): settling hit max deadline (\(maxDeadline)), ending with fallback"
                    )
                    break
                }

                await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: true)
                let managedCount = itemCache.managedItems.count
                let unresolved = itemCache.managedItems.count(where: { $0.sourcePID == nil })
                let pidsOK = managedCount > 0 && unresolved <= 1

                if useExpectedSet {
                    let presentBundleIDs: Set<String> = Set(
                        itemCache.managedItems.compactMap { item in
                            if case let .string(bid) = item.tag.namespace {
                                return bid
                            }
                            return nil
                        }
                    )
                    let stillMissing = waitingFor.subtracting(presentBundleIDs)
                    if stillMissing.isEmpty, pidsOK {
                        MenuBarItemManager.diagLog.debug(
                            "\(reason): all \(waitingFor.count) expected bundle ID(s) reattached, ending early"
                        )
                        break
                    }
                    MenuBarItemManager.diagLog.debug(
                        "\(reason): \(stillMissing.count) bundle ID(s) still missing: \(stillMissing.sorted().joined(separator: ", "))"
                    )
                } else {
                    if pidsOK, managedCount == lastSeenCount {
                        stablePolls += 1
                        if stablePolls >= stableTarget {
                            MenuBarItemManager.diagLog.debug(
                                "\(reason): settled (count=\(managedCount) stable for \(stableTarget) polls, \(unresolved) nil PIDs), ending early"
                            )
                            break
                        }
                    } else {
                        if managedCount != lastSeenCount {
                            MenuBarItemManager.diagLog.debug(
                                "\(reason): count changed \(lastSeenCount) -> \(managedCount) (\(unresolved) nil PIDs), resetting stability"
                            )
                        }
                        stablePolls = 0
                        lastSeenCount = managedCount
                    }
                }

                // Short sleep before next poll; exit immediately if cancelled.
                do {
                    try await Task.sleep(for: .milliseconds(500), tolerance: .milliseconds(100))
                } catch is CancellationError {
                    MenuBarItemManager.diagLog.debug("\(reason): settling task cancelled")
                    return
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else {
                return
            }

            isInStartupSettling = false
            settlingDeadline = nil
            settlingExpectedBundleIDs.removeAll()
            settlingKind = nil
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling period ended"
            )

            // Launch-time profile apply: when a profile is bound to
            // the active display, the profile (not the live
            // savedSectionOrder) is the source of truth for the
            // layout. Without this, the cache cycle below would fire
            // applySavedLayout which restores whatever the live
            // savedSectionOrder happens to be, which can diverge
            // from the profile spec across restarts (manual drags,
            // unmanaged items inserted by NewItemsPlacement, etc.).
            // Awaiting layoutTask ensures the profile apply runs to
            // completion (including arming isApplyingProfileLayout)
            // before the cache cycles below trigger applySavedLayout;
            // that gate then keeps savedOrder from racing the
            // profile apply on launch.
            if let appState = self.appState,
               appState.profileManager.activeProfileID != nil
            {
                MenuBarItemManager.diagLog.info(
                    "\(reason): applying active display profile after settling"
                )
                appState.profileManager.reapplyActiveProfile()
                await appState.profileManager.layoutTask?.value
            }

            MenuBarItemManager.diagLog.debug(
                "\(reason): running fast restore without sourcePID resolution"
            )
            // skipRecentMoveCheck: true; relocateNewLeftmostItems/relocatePendingItems
            // may have stamped lastMoveOperationTimestamp during settling; without this
            // flag the final restore would be silently skipped by the 5 s cooldown.
            await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: false)
            // Final authoritative recache that resolves source PIDs so items used later
            // (which read item.sourcePID ?? item.ownerPID) reflect the true source PID.
            // skipRecentMoveCheck: true ensures this pass is never suppressed by the
            // 1-second recent-move cooldown stamped by the fast restore above.
            await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: true)
        }
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
            Task { [weak self] in
                await self?.cacheItemsRegardless()
                // Many apps register their NSStatusItem more than 1s after
                // didLaunch fires, so the initial cache pass above sees no
                // new window IDs and relocateNewLeftmostItems no-ops. Re-check
                // at +2.5s and +5s to catch late arrivals; cacheItemsIfNeeded
                // bails when window IDs are unchanged, so this is cheap when
                // the item already showed up on the first pass.
                try await Task.sleep(for: .seconds(2.5))
                await self?.cacheItemsIfNeeded()
                try await Task.sleep(for: .seconds(2.5))
                await self?.cacheItemsIfNeeded()
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

        // Periodic check for new menu bar items that appeared after the
        // launch notification follow-ups (e.g. background-only apps like
        // OneDrive that register their NSStatusItem late). Lightweight
        // windowID comparison bails fast when nothing changed.
        cacheTickCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.cacheItemsIfNeeded()
                }
            }

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

// MARK: - Cache Gate

extension MenuBarItemManager {
    /// Serializes cache operations to prevent races between concurrent
    /// `cacheItemsRegardless` calls. When a relocation move is in flight,
    /// a concurrent call could snapshot item positions before the move
    /// completes, caching them in the wrong section.
    ///
    /// Concurrent calls are dropped; the next trigger (space change,
    /// periodic refresh, app launch notification) will pick up changes.
    private actor CacheGate {
        private var isInProgress = false

        func begin() -> Bool {
            guard !isInProgress else { return false }
            isInProgress = true
            return true
        }

        func end() {
            isInProgress = false
        }
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// An actor that manages menu bar item cache operations.
    private final class CacheActor {
        /// Stored task for the current cache operation.
        private var cacheTask: Task<Void, Never>?

        /// A list of the menu bar item window identifiers at the time
        /// of the previous cache.
        private(set) var cachedItemWindowIDs = [CGWindowID]()

        /// A mapping from window identifiers to their resolved source process
        /// identifiers from the previous cache cycle. Used to detect and correct
        /// transient sourcePID resolution errors (e.g. stale AX data after moves).
        private(set) var cachedItemPIDs = [CGWindowID: pid_t]()

        /// Runs the given async closure as a task and waits for it to
        /// complete before returning.
        ///
        /// If a task from a previous call to this method is currently
        /// running, that task is cancelled and replaced.
        func runCacheTask(_ operation: @escaping () async -> Void) async {
            cacheTask?.cancel()
            _ = await cacheTask?.value
            cacheTask = nil
            await operation()
        }

        /// Updates the list of cached menu bar item window identifiers.
        func updateCachedItemWindowIDs(_ itemWindowIDs: [CGWindowID]) {
            cachedItemWindowIDs = itemWindowIDs
        }

        /// Updates the mapping from window identifiers to source process identifiers.
        func updateCachedItemPIDs(_ pids: [CGWindowID: pid_t]) {
            cachedItemPIDs = pids
        }

        /// Clears the list of cached menu bar item window identifiers.
        func clearCachedItemWindowIDs() {
            cachedItemWindowIDs.removeAll()
            cachedItemPIDs.removeAll()
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
    struct ControlItemPair {
        let hidden: MenuBarItem
        let alwaysHidden: MenuBarItem?

        /// Creates a control item pair from already-known control items.
        ///
        /// Used by test fixtures and by callers that have already resolved the
        /// hidden and always-hidden items themselves. Production discovery from
        /// a live menu bar uses the failable initializer below.
        init(hidden: MenuBarItem, alwaysHidden: MenuBarItem?) {
            self.hidden = hidden
            self.alwaysHidden = alwaysHidden
        }

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
        var relocatedItems = [MenuBarItem]()
        let hiddenControlItemBounds: CGRect
        let alwaysHiddenControlItemBounds: [CGRect]

        init(controlItems: ControlItemPair, displayID: CGDirectDisplayID?) {
            self.controlItems = controlItems
            self.cache = ItemCache(displayID: displayID)
            self.hiddenControlItemBounds = Self.bestBounds(for: controlItems.hidden)
            self.alwaysHiddenControlItemBounds = controlItems.alwaysHidden.map { [Self.bestBounds(for: $0)] } ?? []
        }

        private static func bestBounds(for item: MenuBarItem) -> CGRect {
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
            let itemBounds = Self.bestBounds(for: item)

            // Strict-inequality fast path for items that lie entirely on
            // one side of every boundary. Identical to the original
            // semantics so well-behaved items keep their existing
            // classification.
            if itemBounds.minX >= hiddenControlItemBounds.maxX {
                return .visible
            }
            if itemBounds.maxX <= hiddenControlItemBounds.minX {
                if let alwaysHiddenBounds = alwaysHiddenControlItemBounds.first {
                    if itemBounds.minX >= alwaysHiddenBounds.maxX {
                        return .hidden
                    }
                    if itemBounds.maxX <= alwaysHiddenBounds.minX {
                        return .alwaysHidden
                    }
                } else {
                    return .hidden
                }
            }

            // Fall-through: the item straddles at least one boundary.
            // Control items are zero-width markers; any item whose
            // physical bounds cross the marker's single X coordinate
            // fails the strict inequalities above. This happens when a
            // profile collapses a section by moving its control item
            // into the items' physical range, or transiently while
            // sections expand/collapse during section.show()/hide().
            // Returning nil drops the item from the cache and from
            // Phase 1's section sets, which causes the layout to skip
            // the divider move it would otherwise prefer. Resolve every
            // straddle case via midpoint: assign the item to whichever
            // section its physical centre predominantly occupies.
            let itemMid = (itemBounds.minX + itemBounds.maxX) / 2
            let hiddenMid = (hiddenControlItemBounds.minX + hiddenControlItemBounds.maxX) / 2
            if itemMid >= hiddenMid {
                return .visible
            }
            if let alwaysHiddenBounds = alwaysHiddenControlItemBounds.first {
                let ahMid = (alwaysHiddenBounds.minX + alwaysHiddenBounds.maxX) / 2
                return itemMid >= ahMid ? .hidden : .alwaysHidden
            }
            return .hidden
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
                }),
                    context.findSection(for: item) == .visible,
                    temp.originalSection != .visible
                {
                    return temp
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
            let currentBounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
            if currentBounds.origin.x == -1 {
                MenuBarItemManager.diagLog.warning(
                    "Skipping \(item.logString); blocked (x=-1), will retry on next cache tick"
                )
            } else {
                MenuBarItemManager.diagLog.warning(
                    "Couldn't find section for caching \(item.logString) bounds=\(NSStringFromRect(item.bounds)), assigning to hidden"
                )
                context.cache[.hidden].append(item)
            }
        }

        // Count invalid items
        for item in items where !context.isValidForCaching(item) {
            invalidCount += 1
        }

        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: \(validCount) valid, \(invalidCount) invalid (filtered), \(noSectionCount) couldn't find section, \(context.temporarilyShownItems.count) temporarily shown")

        for (item, destination) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination)
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

        if LayoutSolver.shouldPersistSavedOrder(
            isRestoringItemOrder: isRestoringItemOrder,
            isResettingLayout: isResettingLayout,
            isInStartupSettling: isInStartupSettling,
            isApplyingProfileLayout: isApplyingProfileLayout,
            temporarilyShownItemContextsIsEmpty: temporarilyShownItemContexts.isEmpty
        ) {
            // Don't persist if any items are in a transient blocked state (x=-1).
            // Wait for the next cache cycle when bounds are reliable.
            let hasBlockedItems = MenuBarSection.Name.allCases.contains { section in
                context.cache[section].contains { item in
                    let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
                    return bounds.origin.x == -1
                }
            }
            if !hasBlockedItems {
                saveSectionOrder(from: context.cache)
            } else {
                MenuBarItemManager.diagLog.debug(
                    "Skipping saveSectionOrder; blocked items detected (x=-1), will retry on next cache tick"
                )
            }
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
        skipRecentMoveCheck: Bool = false,
        resolveSourcePID: Bool = true,
        skipSavedLayoutApply: Bool = false
    ) async {
        MenuBarItemManager.diagLog.debug(
            "cacheItemsRegardless: entering (skipRecentMoveCheck=\(skipRecentMoveCheck), hasCurrentItemWindowIDs=\(currentItemWindowIDs != nil), resolveSourcePID=\(resolveSourcePID), skipSavedLayoutApply=\(skipSavedLayoutApply))"
        )
        defer {
            backgroundCacheContinuation?.resume()
            backgroundCacheContinuation = nil
        }

        guard skipRecentMoveCheck || !lastMoveOperationOccurred(within: .seconds(1)) else {
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache due to recent item movement")
            return
        }

        guard !(appState?.isDraggingMenuBarItem ?? false) else {
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache: user is cmd-dragging")
            return
        }

        // Serialization gate: drop concurrent calls while a previous cache
        // cycle is in flight. Without this, a call that starts during a
        // relocation move by another call may snapshot pre-move positions.
        guard await cacheGate.begin() else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: serial cache operation already in progress, skipping")
            return
        }
        defer { Task { await cacheGate.end() } }

        let previousWindowIDs = cacheActor.cachedItemWindowIDs
        let displayID = Bridging.getActiveMenuBarDisplayID()
        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: displayID=\(displayID.map { "\($0)" } ?? "nil"), previousWindowIDs count=\(previousWindowIDs.count)")

        var items = await MenuBarItem.getMenuBarItems(
            option: .activeSpace,
            resolveSourcePID: resolveSourcePID
        )

        if items.isEmpty {
            // Retry once after a small delay if we got zero items. This can happen
            // due to transient WindowServer glitches or during display reconfigurations.
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: getMenuBarItems returned ZERO items, retrying in 250ms...")
            try? await Task.sleep(for: .milliseconds(250))
            items = await MenuBarItem.getMenuBarItems(
                option: .activeSpace,
                resolveSourcePID: resolveSourcePID
            )
        }

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: getMenuBarItems returned \(items.count) items")

        // Reconcile resolved sourcePIDs against previously known values to
        // prevent transient resolution errors (e.g. stale AX data after item
        // moves) from corrupting item identities. SourcePIDCache does spatial
        // matching between CG windows and AX extras menu bar children, which
        // can produce wrong matches when AX positions lag behind CG updates.
        // A cached PID from a previous stable cycle is more trustworthy.
        if resolveSourcePID {
            let previousPIDs = cacheActor.cachedItemPIDs
            for i in items.indices {
                let item = items[i]
                guard !item.isControlItem else { continue }
                if let prevPID = previousPIDs[item.windowID],
                   let currentPID = item.sourcePID,
                   currentPID != prevPID
                {
                    MenuBarItemManager.diagLog.warning(
                        "SourcePID changed for windowID \(item.windowID): \(prevPID) -> \(currentPID), reverting to previous PID"
                    )
                    // Rebuild the namespace from the previous PID. If the bundle
                    // ID is not available (app no longer running), keep the
                    // original tag namespace as a safe fallback.
                    let prevBundleID = NSRunningApplication(processIdentifier: prevPID)?.bundleIdentifier
                    let correctedNamespace: MenuBarItemTag.Namespace = if let prevBundleID {
                        .string(prevBundleID)
                    } else {
                        item.tag.namespace
                    }
                    let correctedTag = MenuBarItemTag(
                        namespace: correctedNamespace,
                        title: item.tag.title,
                        windowID: item.windowID,
                        instanceIndex: item.tag.instanceIndex
                    )
                    items[i] = MenuBarItem(
                        tag: correctedTag,
                        windowID: item.windowID,
                        ownerPID: item.ownerPID,
                        sourcePID: prevPID,
                        bounds: item.bounds,
                        title: item.title,
                        isOnScreen: item.isOnScreen
                    )
                }
            }
        }

        // When sourcePID resolution changes an item's identifier (e.g. from
        // com.apple.controlcenter:Item-0:4 to pl.maketheweb.cleanshotx:Item-0),
        // the new identifier won't be in knownItemIdentifiers. Seed it now so
        // the item isn't treated as a "new" item by relocateNewLeftmostItems.
        // Skip items with unresolved sourcePID so the placeholder
        // "com.apple.controlcenter" namespace never enters the persisted set.
        if !previousWindowIDs.isEmpty {
            for item in items where previousWindowIDs.contains(item.windowID) && item.sourcePID != nil {
                let identifier = "\(item.tag.namespace):\(item.tag.title)"
                if !knownItemIdentifiers.contains(identifier) {
                    knownItemIdentifiers.insert(identifier)
                }
            }
            persistKnownItemIdentifiers()
        }

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled after getMenuBarItems")
            return
        }

        if items.isEmpty {
            MenuBarItemManager.diagLog.error("cacheItemsRegardless: getMenuBarItems returned ZERO items even after retry; this is the root cause of 'Loading menu bar items' being stuck")
        }

        let itemWindowIDs = currentItemWindowIDs ?? items.reversed().map(\.windowID)
        cacheActor.updateCachedItemWindowIDs(itemWindowIDs)

        await MainActor.run {
            MenuBarItemTag.Namespace.pruneUUIDCache(keeping: Set(itemWindowIDs))
            self.pruneMoveOperationTimeouts(keeping: Set(items.map(\.tag)))
            self.pruneClickOperationTimeouts(keeping: Set(items.map(\.tag)))
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

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled after control item discovery")
            return
        }

        await enforceControlItemOrder(controlItems: controlItems)

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled before relocateNewLeftmostItems")
            return
        }

        // App-relaunch detection: uniqueIdentifier is namespace:title
        // (windowID-independent and stable across restarts), so a
        // relaunched app keeps the same identifier and would be filtered
        // out of newProfileItems by profileSortedItemIdentifiers in the
        // late-arrival check below. A windowID not in previousWindowIDs
        // for a profile-tracked item means the app re-registered its
        // NSStatusItem at whatever position macOS chose, which is
        // usually not the saved profile position. Drop such identifiers
        // from the sorted snapshot so the late-arrival path picks them
        // up. Run this BEFORE the relocate/restore early returns: those
        // paths schedule a recache after which previousWindowIDs already
        // contains the freshly registered windowID, and the signal would
        // be lost.
        //
        // Position-check refinement: a fresh windowID does not always
        // mean the item is at the wrong position. Idle wake, AX
        // rebinding, and some app lifecycle events recreate the
        // underlying NSStatusItem while macOS retains the original
        // visual position. The earlier unconditional drop fired a
        // full re-sort (which can replan many moves across the bar)
        // on every such event, even when the item was already at its
        // profile-expected section. Gate the drop on a section
        // mismatch: keep items whose current section matches the
        // profile spec, drop only items that genuinely landed in the
        // wrong section. Items whose current section can't be
        // determined (transient bounds during in-flight moves) fall
        // through to the drop path, preserving the original
        // conservative behaviour for ambiguous cases.
        if let activeLayout = activeProfileLayout,
           !activeProfileItemIdentifiers.isEmpty,
           !previousWindowIDs.isEmpty
        {
            let previousWindowIDSet = Set(previousWindowIDs)
            let hiddenMinX = controlItems.hidden.bounds.minX
            let hiddenMaxX = controlItems.hidden.bounds.maxX
            let ahBounds = controlItems.alwaysHidden?.bounds

            // Build per-identifier expected-section lookup from the
            // active profile spec. itemOrder is keyed by section
            // string ("visible" / "hidden" / "alwaysHidden") with
            // identifier arrays for each section.
            var expectedSectionByID = [String: String]()
            for (sectionKey, ids) in activeLayout.itemOrder {
                for id in ids {
                    expectedSectionByID[id] = sectionKey
                }
            }

            // Spatial classification mirrors currentLayoutDivergesFromSaved:
            // visible is right of hiddenCtrl; alwaysHidden is left of
            // ahCtrl when present; hidden is between the two control
            // items (or anything left of hiddenCtrl when ahCtrl is
            // disabled). Items straddling a divider return nil to
            // avoid false positives during transient section
            // show/hide animations.
            func sectionKey(for item: MenuBarItem) -> String? {
                if item.bounds.minX >= hiddenMaxX {
                    return "visible"
                } else if let ahBounds, item.bounds.maxX <= ahBounds.minX {
                    return "alwaysHidden"
                } else if let ahBounds, item.bounds.minX >= ahBounds.maxX, item.bounds.maxX <= hiddenMinX {
                    return "hidden"
                } else if ahBounds == nil, item.bounds.maxX <= hiddenMinX {
                    return "hidden"
                }
                return nil
            }

            let relaunchedIdentifiers = Set(
                items
                    .filter { item in
                        guard !item.isControlItem,
                              !previousWindowIDSet.contains(item.windowID),
                              activeProfileItemIdentifiers.contains(item.uniqueIdentifier)
                        else { return false }
                        // If the item is already at its profile-
                        // expected section, the windowID change was
                        // benign; no re-sort needed. Items whose
                        // current section can't be determined fall
                        // through to the drop path.
                        if let expected = expectedSectionByID[item.uniqueIdentifier],
                           let current = sectionKey(for: item),
                           expected == current
                        {
                            return false
                        }
                        return true
                    }
                    .map(\.uniqueIdentifier)
            )
            let staleSorted = relaunchedIdentifiers.intersection(profileSortedItemIdentifiers)
            if !staleSorted.isEmpty {
                MenuBarItemManager.diagLog.info("Profile re-sort: detected \(staleSorted.count) relaunched profile item(s) with fresh windowID at wrong section: \(staleSorted.sorted())")
                profileSortedItemIdentifiers.subtract(staleSorted)
            }
        }

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

        // Skip all restore logic during the startup settling period.
        // The settling period prevents cascading icon moves when many apps
        // load at login or restart in quick succession (app update checks).
        // A final cacheItemsRegardless() after the period ends handles restore.
        guard !isInStartupSettling else {
            await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)
            // Absorb items that appear during settling into the profile
            // snapshot so they aren't treated as late arrivals afterwards.
            if activeProfileLayout != nil {
                for item in items where !item.isControlItem {
                    profileSortedItemIdentifiers.insert(item.uniqueIdentifier)
                }
            }
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: startup settling active, skipping restore")
            return
        }

        // Unified saved-layout restore: dispatch the bulk apply path
        // when window IDs have changed (app relaunch). applySavedLayout
        // owns its own cooldown and guard checks; applyProfileLayout's
        // body arms isRestoringItemOrder around the moves and drives
        // its own follow-up recache. On rejection the flag is left
        // false so saveSectionOrder can persist the current cache.
        //
        // The skipSavedLayoutApply gate exists so the post-apply
        // refresh scheduled by scheduleDeferredCacheRefresh does NOT
        // re-enter applySavedLayout. Without the gate the deferred
        // refresh runs cacheItemsRegardless → applySavedLayout →
        // dispatch → schedule another refresh, and because consecutive
        // getMenuBarItems calls can return slightly different windowID
        // sets (transient Apple Control Center widgets churn windowIDs
        // even when the visible item count is stable),
        // windowIDsChanged fires on every iteration and the bar enters
        // an infinite no-op apply loop.
        if !skipSavedLayoutApply {
            let didApplySavedLayout = await applySavedLayout(
                items: items,
                previousWindowIDs: previousWindowIDs,
                controlItems: controlItems
            )
            if didApplySavedLayout {
                backgroundCacheContinuation?.resume()
                backgroundCacheContinuation = nil
                return
            }
        }

        await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)

        // Persist the resolved (possibly corrected) sourcePIDs for the next
        // cache cycle so transient resolution errors can be detected.
        // Only update when sourcePIDs were actually resolved; the settle-end
        // fast restore (resolveSourcePID=false) must not overwrite the baseline.
        if resolveSourcePID {
            let newPIDs = Dictionary(
                uniqueKeysWithValues: items.compactMap { item in
                    item.sourcePID.map { (item.windowID, $0) }
                }
            )
            cacheActor.updateCachedItemPIDs(newPIDs)
        }

        // Detect late-arriving items that belong to the active profile.
        if activeProfileLayout != nil,
           !activeProfileItemIdentifiers.isEmpty
        {
            await MainActor.run {
                guard profileResortTask == nil,
                      !isApplyingProfileLayout
                else { return }
                let currentIdentifiers = Set(
                    items
                        .filter { !$0.isControlItem }
                        .map(\.uniqueIdentifier)
                )
                let newProfileItems = currentIdentifiers
                    .intersection(activeProfileItemIdentifiers)
                    .subtracting(profileSortedItemIdentifiers)
                if !newProfileItems.isEmpty {
                    MenuBarItemManager.diagLog.info("Profile re-sort: detected \(newProfileItems.count) late-arriving profile item(s): \(newProfileItems.sorted())")
                    scheduleProfileResort()
                }
            }
        }

        await MainActor.run {
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
        let cachedIDs = cacheActor.cachedItemWindowIDs
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
            static let cache = OSAllocatedUnfairLock(initialState: [CGEventSourceStateID: CGEventSource]())
        }
        if let source = Context.cache.withLock({ $0[stateID] }) {
            return source
        }
        guard let source = CGEventSource(stateID: stateID) else {
            throw EventError.invalidEventSource
        }
        Context.cache.withLock { $0[stateID] = source }
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

    private nonisolated func storeContinuation(
        _ continuation: CheckedContinuation<Void, any Error>,
        in holder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
    ) {
        holder.withLock { $0 = continuation }
    }

    private nonisolated func storeInnerTask(
        _ task: Task<Void, Never>,
        in holder: OSAllocatedUnfairLock<Task<Void, Never>?>
    ) {
        holder.withLock { $0 = task }
    }

    private nonisolated func currentContinuation(
        from holder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
    ) -> CheckedContinuation<Void, any Error>? {
        holder.withLock { $0 }
    }

    private nonisolated func currentInnerTask(
        from holder: OSAllocatedUnfairLock<Task<Void, Never>?>
    ) -> Task<Void, Never>? {
        holder.withLock { $0 }
    }

    private struct EventContinuationContext {
        let event: CGEvent
        let pid: pid_t
        let entryEvent: CGEvent
        let exitEvent: CGEvent
        let firstLocation: EventTap.Location
        let secondLocation: EventTap.Location
    }

    private struct EventContinuationState {
        let countHolder: OSAllocatedUnfairLock<Int>
        let didResume: OSAllocatedUnfairLock<Bool>
        let continuationHolder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
        let innerTaskHolder: OSAllocatedUnfairLock<Task<Void, Never>?>
    }

    private enum EventContinuationKind {
        case postEventBarrier
        case scromble
    }

    private nonisolated func decrementCount(
        in holder: OSAllocatedUnfairLock<Int>
    ) -> Int {
        holder.withLock {
            $0 -= 1
            return $0
        }
    }

    private nonisolated func currentCount(
        from holder: OSAllocatedUnfairLock<Int>
    ) -> Int {
        holder.withLock { $0 }
    }

    private nonisolated func disableEventTaps(_ eventTaps: [EventTap]) {
        for eventTap in eventTaps {
            eventTap.disable()
        }
    }

    private nonisolated func resumeCancellationIfNeeded(
        state: EventContinuationState,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        if state.didResume.tryClaimOnce() {
            continuation.resume(throwing: CancellationError())
        }
    }

    private nonisolated func makeContinuationTask(
        eventTaps: [EventTap],
        state _: EventContinuationState,
        continuation _: CheckedContinuation<Void, any Error>,
        entryEvent: CGEvent,
        firstLocation: EventTap.Location
    ) -> Task<Void, Never> {
        Task {
            for eventTap in eventTaps {
                eventTap.enable()
            }
            entryEvent.post(to: firstLocation)
        }
    }

    private nonisolated func makeEventTap(
        label: String,
        type: CGEventType,
        location: EventTap.Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        handler: @escaping (EventTap, CGEvent) -> CGEvent?
    ) -> EventTap {
        EventTap(
            label: label,
            type: type,
            location: location,
            placement: placement,
            option: option,
            callback: handler
        )
    }

    private nonisolated func makeMenuBarItemEventTap(
        label: String,
        location: EventTap.Location,
        placement: CGEventTapPlacement,
        context: EventContinuationContext,
        onMatch: @escaping (EventTap) -> Void
    ) -> EventTap {
        makeEventTap(
            label: label,
            type: context.event.type,
            location: location,
            placement: placement,
            option: .listenOnly
        ) { tap, rEvent in
            guard rEvent.matches(context.event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                return rEvent
            }
            onMatch(tap)
            // Defensive: Since this EventTap is created with option: .listenOnly,
            // mutating rEvent via setTargetPID is for parity only and will not
            // affect the system event stream.
            rEvent.setTargetPID(context.pid)
            return rEvent
        }
    }

    private nonisolated func makeEntryEventTap(
        context: EventContinuationContext,
        state: EventContinuationState,
        continuation: CheckedContinuation<Void, any Error>
    ) -> EventTap {
        makeEventTap(
            label: "EventTap 1",
            type: .null,
            location: context.firstLocation,
            placement: .headInsertEventTap,
            option: .defaultTap
        ) { tap, rEvent in
            if rEvent.matches(context.entryEvent, byIntegerFields: [.eventSourceUserData]) {
                _ = self.decrementCount(in: state.countHolder)
                context.event.post(to: context.secondLocation)
                return nil
            }
            if rEvent.matches(context.exitEvent, byIntegerFields: [.eventSourceUserData]) {
                tap.disable()
                if state.didResume.tryClaimOnce() {
                    continuation.resume()
                }
                return nil
            }
            return rEvent
        }
    }

    private nonisolated func makeSecondLocationEventTap(
        kind: EventContinuationKind,
        context: EventContinuationContext,
        state: EventContinuationState
    ) -> EventTap {
        makeMenuBarItemEventTap(
            label: "EventTap 2",
            location: context.secondLocation,
            placement: .tailAppendEventTap,
            context: context
        ) { tap in
            switch kind {
            case .postEventBarrier:
                if self.currentCount(from: state.countHolder) <= 0 {
                    tap.disable()
                    context.exitEvent.post(to: context.firstLocation)
                } else {
                    context.entryEvent.post(to: context.firstLocation)
                }
            case .scromble:
                if self.currentCount(from: state.countHolder) <= 0 {
                    tap.disable()
                }
                context.event.post(to: context.firstLocation)
            }
        }
    }

    private nonisolated func makeFirstLocationRelayEventTap(
        context: EventContinuationContext,
        state: EventContinuationState
    ) -> EventTap {
        makeMenuBarItemEventTap(
            label: "EventTap 3",
            location: context.firstLocation,
            placement: .headInsertEventTap,
            context: context
        ) { tap in
            if self.currentCount(from: state.countHolder) <= 0 {
                tap.disable()
                context.exitEvent.post(to: context.firstLocation)
            } else {
                context.entryEvent.post(to: context.firstLocation)
            }
        }
    }

    private nonisolated func makeContinuationEventTaps(
        kind: EventContinuationKind,
        context: EventContinuationContext,
        state: EventContinuationState,
        continuation: CheckedContinuation<Void, any Error>
    ) -> [EventTap] {
        var eventTaps = [
            makeEntryEventTap(
                context: context,
                state: state,
                continuation: continuation
            ),
            makeSecondLocationEventTap(
                kind: kind,
                context: context,
                state: state
            ),
        ]
        if kind == EventContinuationKind.scromble {
            eventTaps.append(
                makeFirstLocationRelayEventTap(
                    context: context,
                    state: state
                )
            )
        }
        return eventTaps
    }

    private nonisolated func awaitEventContinuation(
        kind: EventContinuationKind,
        context: EventContinuationContext,
        state: EventContinuationState,
        eventTaps: inout [EventTap]
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            storeContinuation(continuation, in: state.continuationHolder)

            let continuationEventTaps = makeContinuationEventTaps(
                kind: kind,
                context: context,
                state: state,
                continuation: continuation
            )
            eventTaps.append(contentsOf: continuationEventTaps)

            let innerTask = makeContinuationTask(
                eventTaps: continuationEventTaps,
                state: state,
                continuation: continuation,
                entryEvent: context.entryEvent,
                firstLocation: context.firstLocation
            )
            storeInnerTask(innerTask, in: state.innerTaskHolder)
            if Task.isCancelled { innerTask.cancel() }
        }
    }

    private nonisolated func performEventContinuationOperation(
        _ kind: EventContinuationKind,
        event: CGEvent,
        item: MenuBarItem,
        timeout: Duration,
        repeating count: Int
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

        let countHolder = OSAllocatedUnfairLock(initialState: count)

        let didResume = OSAllocatedUnfairLock(initialState: false)
        let continuationHolder = OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>(initialState: nil)
        let innerTaskHolder = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
        let continuationContext = EventContinuationContext(
            event: event,
            pid: pid,
            entryEvent: entryEvent,
            exitEvent: exitEvent,
            firstLocation: firstLocation,
            secondLocation: secondLocation
        )
        let continuationState = EventContinuationState(
            countHolder: countHolder,
            didResume: didResume,
            continuationHolder: continuationHolder,
            innerTaskHolder: innerTaskHolder
        )

        let timeoutTask = Task(timeout: timeout * count) {
            var eventTaps = [EventTap]()
            defer {
                for tap in eventTaps {
                    tap.invalidate()
                }
            }
            try await withTaskCancellationHandler {
                try await awaitEventContinuation(
                    kind: kind,
                    context: continuationContext,
                    state: continuationState,
                    eventTaps: &eventTaps
                )
            } onCancel: {
                currentInnerTask(from: innerTaskHolder)?.cancel()
                // Directly resume the continuation; handles the common case where
                // innerTask already finished before cancellation was delivered.
                let cont = currentContinuation(from: continuationHolder)
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
        try await performEventContinuationOperation(
            EventContinuationKind.postEventBarrier,
            event: event,
            item: item,
            timeout: timeout,
            repeating: count
        )
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
        try await performEventContinuationOperation(
            EventContinuationKind.scromble,
            event: event,
            item: item,
            timeout: timeout,
            repeating: count
        )
    }
}

// MARK: - Moving Items

extension MenuBarItemManager {
    /// Destinations for menu bar item move operations.
    enum MoveDestination: Equatable {
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
        case .rightOfItem:
            start = CGPoint(x: targetBounds.maxX, y: targetBounds.minY)
        }

        end = start

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
        on displayID: CGDirectDisplayID,
        warpCursorAfter: Bool = true
    ) async throws {
        var acquiredSemaphore = false
        do {
            try await eventSemaphore.wait(timeout: .milliseconds(3500))
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error("eventSemaphore timed out (3.5s) in postMoveEvents")
            await eventSemaphore.reset(to: 1)
            do {
                try await eventSemaphore.wait(timeout: .milliseconds(3500))
                acquiredSemaphore = true
            } catch is SimpleSemaphore.TimeoutError {
                throw EventError.cannotComplete
            }
        }
        defer {
            if acquiredSemaphore {
                Task.detached { [eventSemaphore] in await eventSemaphore.signal() }
            }
        }

        // Fast-fail if the target process is dead. CGEvent.tapCreateForPid
        // silently produces an invalid Mach port for dead PIDs, causing every
        // scrombleEvent to time out and burn the full 3.5 s semaphore budget.
        let eventPID = getEventPID(for: item)
        if kill(eventPID, 0) == -1, errno == ESRCH {
            MenuBarItemManager.diagLog.error("postMoveEvents: target PID \(eventPID) for \(item.logString) is dead; skipping move")
            throw EventError.cannotComplete
        }

        var itemOrigin = try await getCurrentBounds(for: item).origin
        let targetPoints = try await getTargetPoints(forMoving: item, to: destination, on: displayID)
        // Capture mouse location only when this call owns the cursor warp.
        // When called from move(), the outer move() handles the single warp
        // at the end of all attempts so the cursor doesn't oscillate per attempt.
        let mouseLocation: CGPoint? = warpCursorAfter ? try getMouseLocation() : nil
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
        // Skip the warp when the target is offscreen (negative-X items in
        // hidden/always-hidden on notch displays). CGWarpMouseCursorPosition
        // clamps to the display's leftmost edge, which sits under the Apple
        // menu, and the resulting tracking events then route stray clicks
        // there. The 20ms eventSleep that follows the warp is only needed
        // when slow apps have to register the tracking events before the
        // mouseDown; irrelevant offscreen.
        let warpPoint = targetPoints.start
        let warpIsOnScreen = NSScreen.screens.contains { $0.frame.contains(warpPoint) }
        if warpIsOnScreen {
            MouseHelpers.warpCursor(to: warpPoint)
        }
        MouseHelpers.hideCursor()
        if warpIsOnScreen {
            await eventSleep(for: .milliseconds(20))
        }
        // For notched displays, when the target is offscreen, redirect
        // mouseDown's hit-test location into the notch itself. The
        // notch is hardware with no clickable UI, so the OS hit-test
        // there has nothing to dismiss, no menu to open, and no app
        // window to surface a click against. mouseUp keeps its
        // original location (the drop position the receiving app
        // uses to place the item). For non-notched displays the
        // original behaviour is preserved (no override).
        if !warpIsOnScreen {
            let activeScreen = NSScreen.screens.first(where: { $0.displayID == displayID })
                ?? NSScreen.main
            if let activeScreen,
               activeScreen.hasNotch,
               let notch = activeScreen.frameOfNotch
            {
                mouseDown.location = CGPoint(
                    x: notch.midX,
                    y: notch.midY
                )
            }
        }
        defer {
            if let mouseLocation {
                MouseHelpers.warpCursor(to: mouseLocation)
            }
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

    /// Checks if a menu bar item is in a "blocked" state (positioned at x=-1 off-screen).
    /// Items in this state are stuck and cannot be interacted with normally.
    private nonisolated func isItemBlocked(_ item: MenuBarItem) async -> Bool {
        do {
            let bounds = try await getCurrentBounds(for: item)
            // x=-1 is the sentinel value macOS uses for "blocked" items
            return bounds.origin.x == -1
        } catch {
            // If we can't get bounds, assume it's not blocked
            return false
        }
    }

    /// Validates that an item moved to the hidden section didn't get stuck at x=-1.
    /// If the item is blocked, attempts to restore it to the visible section.
    private func validateItemPositionAfterMove(
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async {
        // Only recover items that got stuck when targeting the hidden divider.
        // Items placed adjacent to any other anchor are intentionally positioned;
        // recovering them to visible would undo a correct move.
        switch destination {
        case let .leftOfItem(anchor), let .rightOfItem(anchor):
            guard anchor.tag == .alwaysHiddenControlItem else { return }
        }

        // Check if item got stuck at x=-1
        if await isItemBlocked(item) {
            MenuBarItemManager.diagLog.warning("Item \(item.logString) stuck at x=-1 after move - attempting recovery")

            // Find the control item to use as anchor for recovery
            guard let appState else { return }
            guard let hiddenControlItem = appState.menuBarManager.controlItem(withName: .hidden)?.window else {
                MenuBarItemManager.diagLog.error("Cannot recover item: missing hidden control item window")
                return
            }

            // Create a MenuBarItem representation of the control item for the destination
            // We need to find it in the current cache
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard let hiddenMenuBarItem = items.first(where: { $0.windowID == CGWindowID(hiddenControlItem.windowNumber) }) else {
                MenuBarItemManager.diagLog.error("Cannot recover item: control item not found in menu bar items")
                return
            }

            // Attempt to move the item back to the visible section
            do {
                try await move(
                    item: item,
                    to: .rightOfItem(hiddenMenuBarItem),
                    on: displayID,
                    skipInputPause: true
                )
                MenuBarItemManager.diagLog.info("Successfully recovered \(item.logString) from blocked state to visible section")
            } catch {
                MenuBarItemManager.diagLog.error("Failed to recover \(item.logString) from blocked state: \(error)")
            }
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
        watchdogTimeout: DispatchTimeInterval? = nil,
        maxMoveAttempts: Int = 8
    ) async throws {
        guard item.isMovable else {
            throw EventError.itemNotMovable(item)
        }
        guard let appState else {
            throw EventError.cannotComplete
        }

        // Allow right-of-item moves to proceed even when the item is at x=-1.
        // validateItemPositionAfterMove uses exactly this path to rescue stuck
        // items. Block all other moves: dragging a stuck item deeper into a
        // hidden section could leave it in an unknown position.
        if await isItemBlocked(item) {
            guard case .rightOfItem = destination else {
                MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - item is blocked (x=-1)")
                throw EventError.cannotComplete
            }
            MenuBarItemManager.diagLog.debug("Proceeding with move of blocked \(item.logString); recovery to visible")
        }

        // Determine display ID early.
        let resolvedDisplayID: CGDirectDisplayID = if let displayID {
            displayID
        } else if let window = appState.hidEventManager.bestScreen(appState: appState) {
            window.displayID
        } else {
            Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
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

        // Capture the original cursor position once so the cursor is warped
        // back to it a single time after all attempts, rather than after each
        // individual attempt (which caused the cursor to oscillate many times
        // during a layout reset when items required multiple attempts).
        let mouseLocation = try getMouseLocation()
        // The default 1 s cursor-hide watchdog is too short for menu
        // bar item moves: each item can take up to ~4 s across retries
        // (8 attempts × ~500 ms timeout), and during a full layout pass
        // many items move sequentially. When the watchdog fires partway
        // through, the cursor is force-shown at the synthetic event's
        // last cursorPosition (mid-display, per the offscreen-target
        // override below in postMoveEvents) and the user sees a brief
        // cursor flash. 10 s is long enough to cover any single move
        // without giving up the safety net for genuinely stuck states.
        MouseHelpers.hideCursor(watchdogTimeout: watchdogTimeout ?? .seconds(10))
        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
        }

        // Tracks whether any postMoveEvents attempt produced observable
        // displacement. Only consulted on retries when the item being
        // moved is a zero-width control item (section divider), where
        // a position match can coincide with bounds drifting onto the
        // target externally; ordinary items skip this gate.
        var anyMoveEventsSucceeded = false

        let maxAttempts = max(1, maxMoveAttempts)
        for n in 1 ... maxAttempts {
            guard !Task.isCancelled else {
                throw EventError.cannotComplete
            }
            do {
                if try await itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID) {
                    // On the first iteration trust the position match
                    // unconditionally. On retries, the only case where the
                    // match can be a coincidence is when the item being
                    // moved is itself a zero-width control item; gate
                    // those on observed displacement, accept all others.
                    if n == 1 || anyMoveEventsSucceeded || !item.isControlItem {
                        MenuBarItemManager.diagLog.debug("Item has correct position, finished with move")
                        return
                    }
                    MenuBarItemManager.diagLog.debug(
                        "Position match without observable displacement on attempt \(n); treating as false positive on a zero-width control item and retrying"
                    )
                }
                try await postMoveEvents(
                    item: item,
                    destination: destination,
                    on: resolvedDisplayID,
                    warpCursorAfter: false // move() owns the single warp in its defer
                )
                // postMoveEvents only returns without throwing when both
                // waitForMoveEventResponse calls observed origin changes,
                // i.e. our drag actually displaced the item.
                anyMoveEventsSucceeded = true
                // Verify the item actually reached the correct position.
                if try await itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID) {
                    MenuBarItemManager.diagLog.debug("Attempt \(n) succeeded and verified, finished with move")
                    // Validate that item didn't get stuck when moving to hidden section
                    await validateItemPositionAfterMove(item: item, destination: destination, on: resolvedDisplayID)
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

        // All attempts exhausted without confirmed position. Run the stuck-item
        // validator first (recovers x=-1 blocks), then throw so callers know
        // the item did not reach the destination.
        await validateItemPositionAfterMove(item: item, destination: destination, on: resolvedDisplayID)
        MenuBarItemManager.diagLog.error("move: all \(maxAttempts) attempt(s) exhausted without verifying \(item.logString) reached \(destination.logString)")
        throw EventError.cannotComplete
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
        // Try to acquire semaphore with timeout. 3.5 s covers legitimate slow
        // operations (adaptive click cap is 1000 ms × 2 for double mouseUp =
        // ~2 s of event work plus overhead).
        var acquiredSemaphore = false
        do {
            try await eventSemaphore.wait(timeout: .milliseconds(3500))
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            MenuBarItemManager.diagLog.error("eventSemaphore timed out (3.5s) in postClickEvents for \(item.logString)")
            await eventSemaphore.reset(to: 1)
            do {
                try await eventSemaphore.wait(timeout: .milliseconds(3500))
                acquiredSemaphore = true
            } catch is SimpleSemaphore.TimeoutError {
                throw EventError.cannotComplete
            }
        }
        defer {
            if acquiredSemaphore {
                Task.detached { [eventSemaphore] in await eventSemaphore.signal() }
            }
        }

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

        // Warp the cursor to the click point so the Window Server's hit-test
        // matches the event coordinates rather than the cursor's current position.
        MouseHelpers.warpCursor(to: clickPoint)
        // Small delay to let the Window Server process the warp before posting
        // the event. Without this, the event can be routed using the cursor's
        // old position (e.g. the Apple menu) instead of the warped target.
        try await Task.sleep(for: .milliseconds(10))
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
    /// Clicks a menu bar item with the given mouse button.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    ///   - skipInputPause: Skip waiting for user input to pause.
    ///   - maxAttempts: Maximum number of click attempts (default 3).
    ///     Pass `1` from `temporarilyShow` so a single failure returns
    ///     immediately and the caller's fallback path fires promptly.
    func click(item: MenuBarItem, with mouseButton: CGMouseButton, skipInputPause: Bool = false, maxAttempts: Int = 3) async throws {
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

        let maxAttempts = max(1, maxAttempts)
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
            // First check the tracked popup window; this is the most
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
        /// popup-menu window on screen.
        ///
        /// Only matches the pop-up menu level (the level macOS uses for
        /// menus opened from menu bar items). Status-level and main-menu
        /// level windows are excluded because those are the menu bar items
        /// themselves; including the temporarily-shown item we're
        /// tracking; not popups created by clicking them. A liberal
        /// "above normal" match was previously used as a catch-all, but
        /// it matched floating panels, modal levels, and other unrelated
        /// app windows, keeping `isShowingInterface` true indefinitely
        /// and preventing rehide.
        private func appHasVisiblePopup() -> Bool {
            let windows = WindowInfo.createWindows(option: .onScreen)
            let popUpLevel = CGWindowLevelForKey(.popUpMenuWindow)
            return windows.contains { window in
                guard window.ownerPID == sourcePID else {
                    return false
                }
                let level = CGWindowLevel(Int32(window.layer))
                return level == popUpLevel || level == popUpLevel - 1
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

    /// Waits until the item's Window Server origin differs from `previousOrigin`,
    /// or until `timeout` elapses.
    ///
    /// Used on the fast path of `temporarilyShow` as a lightweight alternative
    /// to `waitForItemPositionToSettle`: we only need to confirm the Window
    /// Server has applied the new position; we don't need two consecutive
    /// identical readings.
    private nonisolated func waitForItemToLeaveOrigin(
        item: MenuBarItem,
        previousOrigin: CGPoint,
        timeout: Duration
    ) async {
        let pollInterval = Duration.milliseconds(15)
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            await eventSleep(for: pollInterval)
            if let currentOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin,
               currentOrigin != previousOrigin
            {
                return
            }
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
        // Debounce so rapid app switches (Cmd-Tab spam) collapse to one
        // rehide attempt instead of queuing a separate Task per change ; 
        // each rehide call can do an expensive on-screen window enumeration.
        rehideCancellable = NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.rehideTemporarilyShownItems()
                }
            }
    }

    /// The result of a ``temporarilyShow(item:clickingWith:on:fastPath:)`` call.
    enum TemporaryShowResult {
        /// The item was never moved; a precondition failed (missing state,
        /// no return destination, no anchor, or the move itself failed).
        /// The item is still hidden; do **not** attempt a fallback click.
        case showFailed
        /// The item was moved into the visible area **and** the synthetic
        /// click completed successfully.
        case movedAndClicked
        /// The item was moved into the visible area but the synthetic click
        /// failed. The icon is now visible; callers may attempt a fallback
        /// click using live bounds.
        case movedButClickFailed
    }

    /// Temporarily moves `item` into the visible area next to the Ice icon,
    /// clicks it, then schedules a rehide.
    ///
    /// The item is returned to its original location after approximately
    /// 15 seconds, though it may be sooner (e.g. when switching apps) or
    /// later due to the smart rehide logic.
    ///
    /// - Returns: A ``TemporaryShowResult`` describing whether the move and
    ///   click succeeded. Only act on ``TemporaryShowResult/movedButClickFailed``
    ///   for fallback clicks; the item is hidden for every other non-success case.
    @discardableResult
    func temporarilyShow(item: MenuBarItem, clickingWith mouseButton: CGMouseButton, on displayID: CGDirectDisplayID? = nil, fastPath: Bool = false) async -> TemporaryShowResult {
        guard let appState else {
            MenuBarItemManager.diagLog.error("Missing AppState, so not showing \(item.logString)")
            return .showFailed
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
        let tagIdentifier = item.tag.tagIdentifier

        // Rehide any previously temporarily shown items before showing a new one.
        // This prevents stale contexts from accumulating when the user opens multiple
        // temporary items in quick succession.
        if !temporarilyShownItemContexts.isEmpty {
            rehideTimer?.invalidate()
            rehideCancellable?.cancel()
            await rehideTemporarilyShownItems(force: true, isCalledFromTemporarilyShow: true)

            // Only treat contexts with rehideAttempts > 0 as genuinely stuck
            // (move was attempted and failed). Contexts with rehideAttempts == 0
            // but notFoundAttempts > 0 are merely not visible on the active
            // space right now; they are transient and will retry fine.
            // Bailing on notFound items would leave them permanently stranded.
            let stuckItems = temporarilyShownItemContexts.filter {
                !$0.tag.matchesIgnoringWindowID(item.tag) && $0.rehideAttempts > 0
            }
            if !stuckItems.isEmpty {
                MenuBarItemManager.diagLog.error(
                    """
                    temporarilyShow: aborting; \(stuckItems.count) item(s) still stuck \
                    after force-rehide: \(stuckItems.map(\.tag)). \
                    Avoiding further semaphore saturation.
                    """
                )
                // Re-arm the rehide timer so stuck contexts are retried rather
                // than left stranded with no scheduled retry.
                runRehideTimer()
                return .showFailed
            }

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
            return .showFailed
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
            return .showFailed
        }

        let moveDestination: MoveDestination = .leftOfItem(anchor)

        // Record the item's original section early so we can relocate it if its app
        // quits before we get a chance to rehide it (macOS persists the
        // physical position set by the Cmd+drag, so on relaunch the icon
        // would otherwise stay in the visible section).
        pendingRelocations[tagIdentifier] = sectionKey(for: originalSection)

        // Also store the return destination to preserve ordering
        let neighborTag = returnInfo.destination.targetItem.tag
        let position = switch returnInfo.destination {
        case .leftOfItem: "left"
        case .rightOfItem: "right"
        }
        pendingReturnDestinations[tagIdentifier] = [
            "neighbor": neighborTag.tagIdentifier,
            "position": position,
        ]
        persistPendingRelocations()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        MenuBarItemManager.diagLog.debug("Temporarily showing \(item.logString) on display \(resolvedDisplayID)")

        // Capture the item's origin before the move so the fast-path settle
        // can detect when the Window Server has applied the new position.
        let preMoveOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin

        do {
            if fastPath {
                // Two-attempt move on the fast path. The first attempt almost always
                // repositions the item correctly; the second is a cheap safety net for
                // the rare case where the event cycle is dropped under CPU load.
                // Keeping retries at 2 (vs. the default 8) avoids the visible jitter
                // from a long retry loop while still tolerating one bad cycle.
                try await move(item: item, to: moveDestination, on: resolvedDisplayID, skipInputPause: true, maxMoveAttempts: 2)
            } else {
                try await move(item: item, to: moveDestination, on: resolvedDisplayID, skipInputPause: true)
            }
        } catch {
            MenuBarItemManager.diagLog.error("Error showing item: \(error)")

            // Determine whether the item physically left its original position
            // despite move() throwing. itemCache is a pre-move snapshot and is
            // not updated during a move() call, so itemCache.address(for:) would
            // always return originalSection here; giving a false negative.
            // Instead, compare live Window Server bounds against the origin
            // captured before the move started. Any nil (window gone or
            // pre-move capture missed) is treated as moved/unknown; preserving
            // rehide metadata is the safe-side choice.
            let currentOrigin = Bridging.getWindowBounds(for: item.windowID)?.origin
            // Treat any nil as "moved/unknown"; preserving rehide metadata is
            // the safe-side choice when the move outcome cannot be determined.
            // Note: in Swift nil != nil evaluates to false, so without the nil
            // guards both-nil would wrongly indicate "item never moved."
            let itemHasMoved = currentOrigin == nil || preMoveOrigin == nil || currentOrigin != preMoveOrigin

            if itemHasMoved {
                // The item is no longer where it started; keep the rehide
                // metadata so the persistent-relocation path can restore it
                // when the app relaunches or the rehide timer fires.
                MenuBarItemManager.diagLog.warning("move() threw but item \(item.logString) is no longer in \(originalSection); preserving pending rehide metadata")
                // pendingRelocations already set above; re-assert return destination
                // in case it was not yet written (guard-exit paths above this block).
                pendingReturnDestinations[tagIdentifier] = [
                    "neighbor": neighborTag.tagIdentifier,
                    "position": position,
                ]
                persistPendingRelocations()
            } else {
                // Item never moved; safe to discard the speculative metadata.
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                persistPendingRelocations()
            }

            return .showFailed
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

        let clickItem: MenuBarItem
        if fastPath {
            // Fast path: lightweight settle (max 150 ms, 15 ms poll) so the
            // click target coordinates are live rather than the pre-move bounds.
            // This is shorter than the full waitForItemPositionToSettle (250 ms)
            // to keep the IceBar click feel snappy.
            if let preMoveOrigin {
                await waitForItemToLeaveOrigin(item: item, previousOrigin: preMoveOrigin, timeout: .milliseconds(150))
            }

            // Re-fetch the item so getCurrentBounds inside postClickEvents
            // uses a fresh window reference rather than the stale pre-move struct.
            let refreshedItems = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .onScreen)
            clickItem = refreshedItems.first(where: { $0.windowID == item.windowID }) ??
                refreshedItems.first(where: {
                    $0.tag.matchesIgnoringWindowID(item.tag) &&
                        ($0.sourcePID ?? $0.ownerPID) == (item.sourcePID ?? item.ownerPID)
                }) ?? item
        } else {
            // Wait for the item's position to stabilize after the move. Some
            // apps need time to process the window relocation before they can
            // correctly position their popup in response to a click.
            await waitForItemPositionToSettle(item: item)

            // Re-fetch the item from the live window list specifically for this display.
            // Prefer an exact windowID match, then fall back to namespace+title with PID matching.
            let refreshedItems = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .onScreen)
            clickItem = refreshedItems.first(where: { $0.windowID == item.windowID }) ??
                refreshedItems.first(where: {
                    $0.tag.matchesIgnoringWindowID(item.tag) &&
                        ($0.sourcePID ?? $0.ownerPID) == (item.sourcePID ?? item.ownerPID)
                }) ?? item

            // Give the owning app a little extra time to finish processing the
            // move internally. Some apps (e.g. OneDrive) need more than just a
            // stable window position before they can respond to clicks.
            await eventSleep(for: .milliseconds(25))
        }

        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))
        let clickPID = clickItem.sourcePID ?? clickItem.ownerPID

        do {
            // Single attempt: the item is already at a known-good position with
            // fresh bounds. If it fails, fall through to the fallback path below
            // rather than spending 3× the semaphore timeout here.
            try await click(item: clickItem, with: mouseButton, skipInputPause: true, maxAttempts: 1)
        } catch {
            MenuBarItemManager.diagLog.error("Error clicking item (first attempt): \(error); attempting fallback click")

            // Fallback: re-fetch the item from the live window list so the
            // click targets a fresh MenuBarItem with current windowID and
            // bounds, rather than the potentially stale pre-click struct.
            let fallbackItems = await MenuBarItem.getMenuBarItems(on: resolvedDisplayID, option: .onScreen)
            let fallbackItem = fallbackItems.first(where: { $0.windowID == clickItem.windowID }) ??
                fallbackItems.first(where: {
                    $0.tag.matchesIgnoringWindowID(clickItem.tag) &&
                        ($0.sourcePID ?? $0.ownerPID) == (clickItem.sourcePID ?? clickItem.ownerPID)
                }) ?? clickItem

            // We stay inside temporarilyShow so that idsBeforeClick and context
            // remain in scope; shownInterfaceWindow can still be captured if
            // the fallback succeeds, keeping isShowingInterface accurate for
            // the rehide logic.
            do {
                try await click(item: fallbackItem, with: mouseButton, skipInputPause: true)
            } catch {
                MenuBarItemManager.diagLog.error("Fallback click also failed for \(item.logString): \(error)")
                // Icon is visible but both click attempts failed.
                return .movedButClickFailed
            }
        }

        // Capture the popup window opened by whichever click path succeeded.
        await eventSleep(for: .milliseconds(100))
        let windowsAfterClick = WindowInfo.createWindows(option: .onScreen)

        context.shownInterfaceWindow = windowsAfterClick.first { window in
            window.ownerPID == clickPID && !idsBeforeClick.contains(window.windowID)
        }

        return .movedAndClicked
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
           let fallbackPID = context.fallbackNeighborPID,
           let freshFallback = items.first(where: {
               $0.tag.matchesIgnoringWindowID(fallbackTag) &&
                   ($0.sourcePID ?? $0.ownerPID) == fallbackPID
           })
        {
            switch context.returnDestination {
            case .leftOfItem:
                return .rightOfItem(freshFallback)
            case .rightOfItem:
                return .leftOfItem(freshFallback)
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
            guard !temporarilyShownItemContexts.contains(where: \.isShowingInterface) else {
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

        // Use a shorter settle time when called from temporarilyShow; the user
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
                // Keep the context for retry; the item may be on another
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
                // Don't remove pendingRelocations; let relocatePendingItems handle it.
                continue
            }

            do {
                try await move(item: item, to: destination, on: context.displayID, skipInputPause: true)
                // Successfully rehidden; remove the pending relocation entry.
                let tagIdentifier = context.tag.tagIdentifier
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
                // Maximum total attempts across all timer rounds.
                // 3 per-call attempts × 3 timer rounds = 9. Beyond this the
                // item is permanently stuck (dead PID, broken EventTap, etc.)
                // and retrying only keeps the event semaphore saturated.
                let maxTotalRehideAttempts = 9
                if context.rehideAttempts < 3 {
                    currentContexts.append(context) // Try again immediately.
                } else if context.rehideAttempts < maxTotalRehideAttempts {
                    // Per-call cap reached; schedule a longer-delay retry.
                    failedContexts.append(context)
                } else {
                    // Total cap reached; drop this context from same-session retries.
                    // Overwrite the pendingRelocations entry with a waitForRelaunch
                    // sentinel so relocatePendingItems() skips move() this session.
                    // The sentinel encodes the current windowID; when the app
                    // relaunches its status item gets a new windowID, clearing the
                    // suppression automatically.
                    let tagIdentifier = context.tag.tagIdentifier
                    pendingRelocations[tagIdentifier] = waitForRelaunchValue(
                        windowID: item.windowID,
                        section: context.originalSection
                    )
                    persistPendingRelocations()
                    MenuBarItemManager.diagLog.error(
                        """
                        Giving up rehide for \(item.logString) after \
                        \(context.rehideAttempts) total attempts; \
                        marked waitForRelaunch; relocatePendingItems will \
                        retry only after app relaunch (new windowID)
                        """
                    )
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
                \(failedContexts.map(\.tag))
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
        let tagIdentifier = tag.tagIdentifier
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
            // Skip items with unresolved sourcePID so the placeholder
            // "com.apple.controlcenter" namespace never enters the persisted set.
            let identifiers = items
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map { "\($0.tag.namespace):\($0.tag.title)" }
            knownItemIdentifiers.formUnion(identifiers)
            persistKnownItemIdentifiers()
            suppressNextNewLeftmostItemRelocation = false
            return false
        }

        // During startup settling, the first cache pass may have items tagged
        // with wrong namespaces (e.g. com.apple.controlcenter when sourcePID
        // hasn't resolved yet). Using those wrong tags to build hiddenTags /
        // alwaysHiddenTags causes ALL items to appear as "new" on the next
        // pass with correct sourcePIDs, triggering a destructive relocation
        // cascade that moves every hidden/always-hidden item to visible.
        // Seed identifiers and skip relocation; the settling-end restore pass
        // will handle correct placement.
        if isInStartupSettling {
            // Skip items with unresolved sourcePID so the placeholder
            // "com.apple.controlcenter" namespace never enters the persisted set.
            let identifiers = items
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map { "\($0.tag.namespace):\($0.tag.title)" }
            knownItemIdentifiers.formUnion(identifiers)
            persistKnownItemIdentifiers()
            return false
        }

        // Cached hidden / always-hidden tags from the prior cache cycle.
        // The planner uses these to short-circuit re-relocating items
        // already placed in a hidden section.
        let hiddenTags = Set(itemCache[.hidden].map(\.tag))
        let alwaysHiddenTags = Set(itemCache[.alwaysHidden].map(\.tag))

        // Pre-compute live state for the planner. hiddenBounds and the
        // section classification both require the live Window Server;
        // computing them here keeps planLeftmostMove pure over its inputs.
        let hiddenBounds = bestBounds(for: controlItems.hidden)
        var sectionContext = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )
        var sectionByWindowID = [CGWindowID: MenuBarSection.Name]()
        for item in items {
            if let section = sectionContext.findSection(for: item) {
                sectionByWindowID[item.windowID] = section
            }
        }

        let decision = LayoutSolver.planLeftmostMove(
            items: items,
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: sectionByWindowID,
                previousWindowIDs: previousWindowIDs
            ),
            savedSectionOrder: savedSectionOrder,
            knownItemIdentifiers: knownItemIdentifiers,
            hiddenTags: hiddenTags,
            alwaysHiddenTags: alwaysHiddenTags,
            effectiveNewItemsSection: effectiveNewItemsSection
        )

        switch decision {
        case let .thawIcon(thawIcon):
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

        case let .systemItem(systemItem):
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

        case let .newHideableItem(candidate, identifierToMark):
            // Track this item so future cache cycles don't treat it as new.
            knownItemIdentifiers.insert(identifierToMark)
            persistKnownItemIdentifiers()

            let destination = newItemsMoveDestination(for: controlItems, among: items)

            MenuBarItemManager.diagLog.info(
                "Relocating new item \(candidate.logString) to \(effectiveNewItemsSection.logString)"
            )

            // Skip items with no valid bounds (transient clone windows
            // etc.). This live check stays in the orchestrator because
            // it requires Bridging.
            guard Bridging.getWindowBounds(for: candidate.windowID) != nil else {
                MenuBarItemManager.diagLog.warning("Skipping relocation for \(candidate.logString); no valid bounds, likely transient")
                return false
            }

            do {
                try await move(
                    item: candidate,
                    to: destination,
                    skipInputPause: true
                )
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate \(candidate.logString): \(error)")
                return false
            }
            return true

        case let .noop(reason):
            switch reason {
            case .unresolvedSourcePID:
                MenuBarItemManager.diagLog.debug(
                    "relocateNewLeftmostItems: skipping, hideable items have unresolved sourcePIDs"
                )
            case .alreadyInTarget:
                MenuBarItemManager.diagLog.debug(
                    "relocateNewLeftmostItems: candidate already in \(effectiveNewItemsSection.logString), skipping"
                )
            case .noNewCandidate, .noLeftmostItems:
                break
            }
            return false
        }
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

        // Don't interfere with items that are currently temporarily shown ; 
        // those are handled by the normal rehide flow.
        let activelyShownTags = Set(temporarilyShownItemContexts.map(\.tag.tagIdentifier))

        let hiddenBounds = bestBounds(for: controlItems.hidden)

        // Pre-compute live per-item bounds for the planner's "already in
        // hidden section" comparison. Done here so the planner stays pure
        // over its inputs (no Bridging calls inside).
        var boundsForWindowID = [CGWindowID: CGRect]()
        for item in items {
            boundsForWindowID[item.windowID] = bestBounds(for: item)
        }

        // Extract fallback neighbor tags from temporarilyShownItemContexts.
        // The planner only needs the tag-identifier → neighbor mapping;
        // exposing the full context type to the planner would tangle its
        // signature with private state.
        var fallbackNeighborByTagIdentifier = [String: MenuBarItemTag]()
        for context in temporarilyShownItemContexts {
            if let neighbor = context.fallbackNeighborTag {
                fallbackNeighborByTagIdentifier[context.tag.tagIdentifier] = neighbor
            }
        }

        var didRelocate = false

        // Iterate a snapshot of the dict keys so promotions of waitForRelaunch
        // sentinels mid-loop don't disturb iteration. The planner is called
        // per entry; the orchestrator handles persistence and re-runs after
        // a promotion so the regular section path executes.
        let allTagIdentifiers = Array(pendingRelocations.keys)
        for tagIdentifier in allTagIdentifiers {
            guard let rawSectionString = pendingRelocations[tagIdentifier] else { continue }

            // Parse the raw string into a typed PendingEntry for the planner.
            let entry: PendingLedger.PendingEntry
            if let sentinel = parseWaitForRelaunch(rawSectionString) {
                entry = PendingLedger.PendingEntry(
                    tagIdentifier: tagIdentifier,
                    kind: .waitForRelaunch(windowID: sentinel.windowID, section: sentinel.section)
                )
            } else if let parsedSection = sectionName(for: rawSectionString) {
                entry = PendingLedger.PendingEntry(tagIdentifier: tagIdentifier, kind: .section(parsedSection))
            } else {
                // Malformed entry; drop it.
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)
                continue
            }

            var decision = PendingLedger.planPendingMove(
                entry: entry,
                items: items,
                controlItems: controlItems,
                hiddenBounds: hiddenBounds,
                boundsForWindowID: boundsForWindowID,
                activelyShownTags: activelyShownTags,
                returnInfo: PendingLedger.PendingReturnInfo(
                    destinations: pendingReturnDestinations,
                    fallbackNeighbors: fallbackNeighborByTagIdentifier
                )
            )

            // Handle a sentinel promotion in-place: rewrite pendingRelocations
            // to the regular section key, persist, then re-run the planner
            // for the same entry so the regular section path executes.
            if case let .promoteWaitForRelaunch(promotedSection) = decision {
                if let item = items.first(where: { entry.tagIdentifier == $0.tag.tagIdentifier }) {
                    MenuBarItemManager.diagLog.info(
                        "relocatePendingItems: \(item.logString) has new windowID; clearing waitForRelaunch sentinel"
                    )
                }
                pendingRelocations[tagIdentifier] = sectionKey(for: promotedSection)
                persistPendingRelocations()

                let promotedEntry = PendingLedger.PendingEntry(tagIdentifier: tagIdentifier, kind: .section(promotedSection))
                decision = PendingLedger.planPendingMove(
                    entry: promotedEntry,
                    items: items,
                    controlItems: controlItems,
                    hiddenBounds: hiddenBounds,
                    boundsForWindowID: boundsForWindowID,
                    activelyShownTags: activelyShownTags,
                    returnInfo: PendingLedger.PendingReturnInfo(
                        destinations: pendingReturnDestinations,
                        fallbackNeighbors: fallbackNeighborByTagIdentifier
                    )
                )
            }

            switch decision {
            case let .move(item, destination):
                let targetSection: MenuBarSection.Name = {
                    if case let .section(section) = entry.kind { return section }
                    if case let .waitForRelaunch(_, section) = entry.kind { return section }
                    return .hidden
                }()
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

            case .clearEntry:
                pendingRelocations.removeValue(forKey: tagIdentifier)
                pendingReturnDestinations.removeValue(forKey: tagIdentifier)

            case .promoteWaitForRelaunch:
                // Unreachable: handled above by re-running the planner with
                // the promoted entry. If the planner returns promote a
                // second time we just leave the entry alone for next pass.
                break

            case let .skip(reason):
                switch reason {
                case .waitForRelaunchActive:
                    if let item = items.first(where: { entry.tagIdentifier == $0.tag.tagIdentifier }) {
                        MenuBarItemManager.diagLog.debug(
                            "relocatePendingItems: skipping \(item.logString); waitForRelaunch sentinel active (same windowID)"
                        )
                    }
                case .activelyShown, .itemNotPresent:
                    break
                }
            }
        }

        persistPendingRelocations()
        return didRelocate
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
        let cacheFreshness: Duration = .milliseconds(250)

        if let cachedAt = menuOpenCheckCachedAt,
           cachedAt.duration(to: .now) <= cacheFreshness,
           menuOpenCheckCachedResult == true
        {
            MenuBarItemManager.diagLog.debug("Menu open check: using cached result true")
            return true
        }

        if let existingTask = menuOpenCheckTask {
            MenuBarItemManager.diagLog.debug("Menu open check: joining in-flight probe")
            return await existingTask.value
        }

        let cachedItems = itemCache.managedItems.filter(\.isOnScreen)
        let controlCenterBundleID = MenuBarItemTag.Namespace.controlCenter.description

        let task = Task.detached(priority: .utility) { () -> Bool in
            // Get all on-screen windows.
            let windows = WindowInfo.createWindows(option: .onScreen)
            let potentialMenuWindows = windows.filter { window in
                guard window.isMenuRelated, window.title?.isEmpty ?? true else {
                    return false
                }
                guard window.owningApplication?.bundleIdentifier != controlCenterBundleID else {
                    MenuBarItemManager.diagLog.debug(
                        "Skipping Control Center window: PID \(window.ownerPID), title: \(window.title ?? "nil")"
                    )
                    return false
                }
                return true
            }

            guard !potentialMenuWindows.isEmpty else {
                MenuBarItemManager.diagLog.debug(
                    "Menu open check: no candidate menu windows on screen"
                )
                return false
            }

            let fastPathPIDs = Set(cachedItems.compactMap { item -> pid_t? in
                if let sourcePID = item.sourcePID {
                    return sourcePID
                }
                guard item.owningApplication?.bundleIdentifier != controlCenterBundleID else {
                    return nil
                }
                return item.ownerPID
            })

            MenuBarItemManager.diagLog.debug(
                """
                Checking for open menus - fast path with \(cachedItems.count) cached menu bar items, \
                \(fastPathPIDs.count) candidate PIDs, \(potentialMenuWindows.count) candidate menu windows
                """
            )

            let fastPathResult = potentialMenuWindows.contains { window in
                let isMenuOpen = fastPathPIDs.contains(window.ownerPID)
                if isMenuOpen {
                    MenuBarItemManager.diagLog.debug(
                        """
                        Found open menu window on fast path: PID \(window.ownerPID), \
                        owner: \(window.ownerName as NSObject?), title: \(window.title ?? "nil"), \
                        isMenuRelated: \(window.isMenuRelated)
                        """
                    )
                }
                return isMenuOpen
            }

            if fastPathResult {
                MenuBarItemManager.diagLog.debug("Menu open check result: true (fast path)")
                return true
            }

            let unresolvedWindows = WindowInfo.createWindows(
                from: cachedItems.compactMap { item in
                    guard item.sourcePID == nil, !item.isControlItem else {
                        return nil
                    }
                    guard item.owningApplication?.bundleIdentifier == controlCenterBundleID else {
                        return nil
                    }
                    return item.windowID
                }
            )

            guard !unresolvedWindows.isEmpty else {
                MenuBarItemManager.diagLog.debug("Menu open check result: false (fast path)")
                return false
            }

            MenuBarItemManager.diagLog.debug(
                "Menu open check: precise fallback resolving \(unresolvedWindows.count) unresolved window source PIDs"
            )

            let resolvedPIDs = await MenuBarItemManager.resolveAllSourcePIDs(for: unresolvedWindows)

            let precisePIDs = fastPathPIDs.union(resolvedPIDs)
            let result = potentialMenuWindows.contains { window in
                let isMenuOpen = precisePIDs.contains(window.ownerPID)
                if isMenuOpen {
                    MenuBarItemManager.diagLog.debug(
                        """
                        Found open menu window on precise fallback: PID \(window.ownerPID), \
                        owner: \(window.ownerName as NSObject?), title: \(window.title ?? "nil"), \
                        isMenuRelated: \(window.isMenuRelated)
                        """
                    )
                }
                return isMenuOpen
            }

            MenuBarItemManager.diagLog.debug(
                "Menu open check result: \(result) (precise fallback with \(resolvedPIDs.count) resolved PIDs)"
            )
            return result
        }

        menuOpenCheckTask = task
        let result = await task.value
        menuOpenCheckTask = nil
        if result {
            menuOpenCheckCachedResult = true
            menuOpenCheckCachedAt = .now
        } else {
            menuOpenCheckCachedResult = nil
            menuOpenCheckCachedAt = nil
        }
        return result
    }

    private static nonisolated func resolveAllSourcePIDs(for windows: [WindowInfo]) async -> Set<pid_t> {
        let pids = await MenuBarItemService.Connection.shared.sourcePIDs(for: windows)
        return Set(pids.compactMap(\.self))
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
        // A user-initiated reset is authoritative: end the startup settling period
        // immediately so that the post-reset cache is not blocked from running restore
        // and saveSectionOrder by an in-flight settling task.
        startupSettlingTask?.cancel()
        isInStartupSettling = false
        settlingDeadline = nil
        settlingExpectedBundleIDs.removeAll()
        settlingKind = nil
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

        // Clear active profile layout cache.
        activeProfileLayout = nil
        activeProfileItemIdentifiers.removeAll()
        profileSortedItemIdentifiers.removeAll()
        profileResortTask?.cancel()
        profileResortTask = nil
        persistKnownItemIdentifiers()
        persistPinnedBundleIDs()
        persistPendingRelocations()
        persistSavedSectionOrder()
        temporarilyShownItemContexts.removeAll()

        // Reset new items placement to default.
        newItemsPlacement = NewItemsPlacement.defaultValue
        Defaults.removeObject(forKey: .newItemsSection)
        Defaults.removeObject(forKey: .newItemsPlacementData)

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

        appState.menuBarManager.iceBarPanel.close()

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

        cacheActor.clearCachedItemWindowIDs()
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

        // Clear any stale -1 sentinel that may have been written into
        // menuBarHeightCache while the Menubar window was transiently
        // unavailable during the reset. The item cache is fully rebuilt
        // at this point, so the next mouse event will perform a fresh
        // live lookup and cache the correct height.
        NSScreen.invalidateMenuBarHeightCache()

        return failedMoves
    }

    /// Wrapper for UI callers; kept separate for clarity in call sites.
    @MainActor
    func resetLayoutFromSettingsPane() async throws -> Int {
        try await resetLayoutToFreshState()
    }

    /// Ends an in-flight settling period immediately. Used by paths that
    /// pre-flight a settling period before a potentially-no-op spacing
    /// apply: when applyOffset turns out not to relaunch anything, the
    /// pre-flight is cancelled so subsequent restore logic isn't
    /// suppressed unnecessarily.
    ///
    /// Refuses to cancel a settling that has already been promoted to
    /// expected-set mode by a real relaunch wave. Otherwise a concurrent
    /// no-op apply (typically from a duplicate screenParametersChanged
    /// notification that finds the on-disk spacing already correct) would
    /// tear down the wait for those bundle IDs to reattach, leaving
    /// applyProfileLayout to run against a half-populated cache.
    func cancelSettlingPeriod(reason: String) {
        guard isInStartupSettling || startupSettlingTask != nil else { return }
        if !settlingExpectedBundleIDs.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling cancel ignored; \(settlingExpectedBundleIDs.count) expected bundle ID(s) still pending"
            )
            return
        }
        // Cold-boot settling is authoritative. A noOp from a boot-time
        // applyOffset that found on-disk values already correct must not
        // tear it down; many menu bar apps haven't reattached yet, and
        // applyProfileLayout would then run against a half-populated cache
        // and silently report "all items already in correct positions".
        if settlingKind == .cold {
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling cancel ignored; performSetup settling in flight"
            )
            return
        }
        startupSettlingTask?.cancel()
        startupSettlingTask = nil
        isInStartupSettling = false
        settlingDeadline = nil
        settlingKind = nil
        MenuBarItemManager.diagLog.debug("\(reason): settling period cancelled")
    }

    /// Schedules a debounced re-application of the active profile's layout
    /// to place late-arriving items in their correct positions. Multiple
    /// calls within the debounce window are coalesced into a single re-sort.
    private func scheduleProfileResort() {
        profileResortTask?.cancel()
        profileResortTask = Task { [weak self] in
            // Short debounce to coalesce multiple items appearing in quick
            // succession. The app-launch notification already has a 1s debounce,
            // so this only needs to cover the gap between detection and action.
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return // Cancelled; a newer schedule replaced us.
            }
            guard let self, let layout = self.activeProfileLayout else { return }
            guard !self.isInStartupSettling else { return }
            guard !self.isRestoringItemOrder else { return }

            MenuBarItemManager.diagLog.info("Profile re-sort: re-applying layout for late-arriving items")
            // Clear profileResortTask BEFORE calling applyProfileLayout,
            // because applyProfileLayout cancels profileResortTask to
            // prevent concurrent re-sorts; which would cancel THIS task
            // and cause the move loop to exit via Task.isCancelled.
            self.profileResortTask = nil
            await self.applyProfileLayout(
                pinnedHidden: layout.pinnedHidden,
                pinnedAlwaysHidden: layout.pinnedAlwaysHidden,
                sectionOrder: layout.sectionOrder,
                itemSectionMap: layout.itemSectionMap,
                itemOrder: layout.itemOrder
            )
        }
    }

    /// Clears the cached active profile layout, stopping any pending
    /// late-arrival re-sort. Called when the active profile is cleared.
    func clearActiveProfileLayout() {
        activeProfileLayout = nil
        activeProfileItemIdentifiers.removeAll()
        profileSortedItemIdentifiers.removeAll()
        profileResortTask?.cancel()
        profileResortTask = nil
        isApplyingProfileLayout = false
    }

    /// Awaits the end of the startup settling window before returning.
    ///
    /// Loops in case performSetup re-enters mid-await (e.g. a permission
    /// re-grant during login): re-entry cancels the captured task and
    /// starts a new settling window, so resuming on a single captured
    /// task could land back inside an active window. Re-check
    /// isInStartupSettling after each await and pick up the current
    /// startupSettlingTask.
    private func waitForStartupSettlingToEnd() async {
        while isInStartupSettling {
            guard let settlingTask = startupSettlingTask else { break }
            MenuBarItemManager.diagLog.debug(
                "applyProfileLayout: waiting for startup settling to end"
            )
            await settlingTask.value
        }
    }

    /// Applies a profile's layout by moving items to match the profile's
    /// saved section assignments and within-section ordering.
    ///
    /// Uses per-item identifiers (not just bundle IDs) to correctly handle
    /// apps like Control Center that share a single bundle ID across many
    /// items (WiFi, Battery, etc.).
    ///
    /// The approach processes each section's saved item order and moves items
    /// into position one at a time, achieving both correct section placement
    /// and correct ordering in a single pass.
    /// Source of an applyProfileLayout invocation. Determines which
    /// pieces of class-level state are armed at entry and cleared at
    /// exit. The shared body (discovery, unmanaged placement, notch
    /// overflow, execution) is identical regardless of source.
    ///
    /// - profile: applying a profile spec. The spec overwrites
    ///   savedSectionOrder, pinning sets, and activeProfileLayout;
    ///   isApplyingProfileLayout gates concurrent restores; the
    ///   profile-sorted snapshot updates at exit for late-arrival
    ///   detection.
    /// - savedOrder: re-applying the user's saved layout (no profile
    ///   spec involved). savedSectionOrder is already the source of
    ///   truth and is not overwritten; pinning is preserved;
    ///   activeProfileLayout is not touched. Only isRestoringItemOrder
    ///   is armed.
    enum ApplySource {
        case profile
        case savedOrder
    }

    /// Arms in-memory profile state and the in-flight gate. No-op for
    /// .savedOrder so the saved-layout path skips profile-specific
    /// arming. Centralises the field set so adding a profile-scoped
    /// field touches one place.
    ///
    /// Disk persistence is deferred to persistProfileStateOnSuccess,
    /// which runs only after the bulk apply reaches a success exit
    /// (Phase 6 finished, an early-return for "already in target", or
    /// Phase 7 with Task.isCancelled false). If a crash, SIGKILL, or
    /// mid-apply cancellation aborts before that point, disk reflects
    /// the previous profile rather than an unexecuted intent.
    private func armProfileState(
        source: ApplySource,
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) {
        guard case .profile = source else { return }
        pinnedHiddenBundleIDs = pinnedHidden
        pinnedAlwaysHiddenBundleIDs = pinnedAlwaysHidden
        savedSectionOrder = sectionOrder

        profileResortTask?.cancel()
        profileResortTask = nil
        isApplyingProfileLayout = true
        activeProfileLayout = (
            pinnedHidden: pinnedHidden,
            pinnedAlwaysHidden: pinnedAlwaysHidden,
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )
        activeProfileItemIdentifiers = Set(itemOrder.values.flatMap(\.self))
    }

    /// Persists the profile's pinning sets and saved section order to
    /// disk. Called from each applyProfileLayout success exit so the
    /// on-disk intent only commits once the bar reflects it. No-op for
    /// .savedOrder (that path doesn't overwrite either store).
    private func persistProfileStateOnSuccess(source: ApplySource) {
        guard case .profile = source else { return }
        persistPinnedBundleIDs()
        persistSavedSectionOrder()
    }

    /// Refreshes profileSortedItemIdentifiers from the supplied item
    /// set. Called from each apply early-return so late-arrival re-sort
    /// doesn't keep re-triggering for items already evaluated. No-op
    /// for .savedOrder (no active profile to track).
    private func updateProfileSortedSnapshot(source: ApplySource, items: [MenuBarItem]) {
        guard case .profile = source else { return }
        profileSortedItemIdentifiers = Set(
            items
                .filter { !$0.isControlItem }
                .map(\.uniqueIdentifier)
        )
    }

    /// Profile-only exit cleanup: refresh the sorted snapshot and clear
    /// the in-flight profile flag. No-op for .savedOrder.
    private func clearProfileState(source: ApplySource, items: [MenuBarItem]) {
        updateProfileSortedSnapshot(source: source, items: items)
        guard case .profile = source else { return }
        isApplyingProfileLayout = false
    }

    /// Schedules the post-apply refresh sequence on a detached Task:
    /// a full cache cycle (which updates itemCache, re-runs the
    /// relocate paths and persists savedSectionOrder if appropriate),
    /// then imageCache cleanup and an observer notification.
    ///
    /// applyProfileLayout's exit points (Phase 7 normal exit plus the
    /// Phase 6 early-returns) cannot inline-await cacheItemsRegardless
    /// because they're inside a body that the outer cacheItemsRegardless
    /// is awaiting via applySavedLayout. The outer call holds its
    /// serial cacheGate across that await, so an inline recursive call
    /// is rejected with "serial cache operation already in progress,
    /// skipping" and itemCache stays stale (the field-reported symptom:
    /// quit apps still appear in Settings Layout, ThawBar, and Search
    /// until something else triggers a non-applySavedLayout cache
    /// cycle). Spawning a Task defers execution until after the outer
    /// releases the gate, mirroring the relocate-path recache pattern.
    /// The uiSettleDelay gives WindowServer a tick to settle the moves
    /// (or, for early-returns, the windowID churn that triggered the
    /// apply) before the next snapshot.
    private func scheduleDeferredCacheRefresh() {
        Task { [weak self] in
            try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
            guard let self else { return }
            // skipSavedLayoutApply=true breaks the dispatch loop: the
            // apply already ran (we're scheduling a refresh after it);
            // re-entering applySavedLayout here would re-trigger on
            // any transient windowID-set churn and live-lock the bar.
            // Cache update + save still run via uncheckedCacheItems.
            await self.cacheItemsRegardless(
                skipRecentMoveCheck: true,
                skipSavedLayoutApply: true
            )
            guard let appState = self.appState else { return }
            appState.imageCache.performCacheCleanup()
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            await MainActor.run { appState.objectWillChange.send() }
        }
    }

    func applyProfileLayout(
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]],
        source: ApplySource = .profile
    ) async {
        // MARK: Phase 0: gate on startup settling
        //
        // During settling, cacheItemsRegardless skips restore and
        // absorbs every current item into profileSortedItemIdentifiers;
        // a layout applied here has its moves silently shadowed and the
        // late-arrival re-sort path is broken for items that appeared
        // inside the window.
        await waitForStartupSettlingToEnd()

        // Bail before arming any profile state if cancellation arrived
        // during the settling wait (a newer apply has replaced us via
        // applyProfile's layoutTask?.cancel()).
        if Task.isCancelled { return }

        // MARK: Phase 1: persist state and arm in-flight flags
        // Profile-only: overwrite the persisted layout state with the
        // profile spec and arm activeProfileLayout / late-arrival
        // tracking. The savedOrder path keeps savedSectionOrder
        // unchanged (it IS the source) and skips activeProfileLayout
        // entirely; the relocateNewLeftmostItems path handles
        // late-arrivals for non-profile restores.
        armProfileState(
            source: source,
            pinnedHidden: pinnedHidden,
            pinnedAlwaysHidden: pinnedAlwaysHidden,
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )

        // Prevent the cache cycle from saving intermediate positions.
        // Shared across both sources: the apply moves items in flight
        // regardless of trigger, and saveSectionOrder must not capture
        // those intermediate states.
        isRestoringItemOrder = true
        isRestoringItemOrderTimestamp = Date()
        defer {
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        guard let appState else {
            MenuBarItemManager.diagLog.error("applyProfileLayout: missing appState")
            return
        }
        guard !itemOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applyProfileLayout: no item order, skipping")
            return
        }

        // MARK: Phase 2: discover items, classify sections, build sequences
        let hiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        // Build desired flat sequence (right-to-left): visible, hidden, alwaysHidden.
        // This is the target linear order of all items across all sections.
        // Control item UIDs are inserted at section boundaries after the
        // items are discovered (since we need the ControlItemPair first).
        var desiredFlat = [String]()
        for key in ["visible", "hidden", "alwaysHidden"] {
            if let order = itemOrder[key] {
                desiredFlat.append(contentsOf: order)
            }
        }

        // Discover current items and build current flat sequence (right-to-left).
        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard var itemsCopy = Optional(items),
              let controlItems = ControlItemPair(
                  items: &itemsCopy,
                  hiddenControlItemWindowID: hiddenWID,
                  alwaysHiddenControlItemWindowID: alwaysHiddenWID
              )
        else {
            MenuBarItemManager.diagLog.error("applyProfileLayout: missing control items")
            return
        }

        // Build current flat sequence grouped by section (same structure as desired).
        // Raw X-position order interleaves sections and gives bad LCS results.
        var context = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )

        func isProfileItem(_ item: MenuBarItem) -> Bool {
            (item.canBeHidden || item.tag == .visibleControlItem) && item.isMovable
        }

        let hiddenCtrlUID = controlItems.hidden.uniqueIdentifier
        let ahCtrlUID = controlItems.alwaysHidden?.uniqueIdentifier

        // Snapshot each item's current section ONCE so the cache-log loop
        // and Phase 1 below see identical classifications. context.findSection
        // re-queries the Window Server via Bridging.getWindowBounds on every
        // call. Between the cache-log iteration (a few lines below) and the
        // Phase 1 iteration further down, the transient bounds reported
        // during a section.show()-driven control-item move can flip an
        // item's classification, producing empty currentHiddenSet and
        // currentAHSet that let Phase 1 skip the AH_ctrl move when items
        // legitimately need to cross the hidden↔always-hidden boundary.
        // Indexed by windowID because items duplicated across displays
        // share a uniqueIdentifier but have distinct windows; storing per
        // window preserves each instance's own classification.
        var sectionByWindowID: [CGWindowID: MenuBarSection.Name] = [:]
        for item in items where isProfileItem(item) {
            if let section = context.findSection(for: item) {
                sectionByWindowID[item.windowID] = section
            }
        }

        // Rebuild desiredFlat with control items at section boundaries.
        var sectionMap = itemSectionMap
        var desiredFlatWithControls = [String]()
        if let order = itemOrder["visible"] {
            desiredFlatWithControls.append(contentsOf: order)
        }
        desiredFlatWithControls.append(hiddenCtrlUID)
        sectionMap[hiddenCtrlUID] = "hidden"
        if let order = itemOrder["hidden"] {
            desiredFlatWithControls.append(contentsOf: order)
        }
        if let ahCtrlUID {
            desiredFlatWithControls.append(ahCtrlUID)
            sectionMap[ahCtrlUID] = "alwaysHidden"
        }
        if let order = itemOrder["alwaysHidden"] {
            desiredFlatWithControls.append(contentsOf: order)
        }
        desiredFlat = desiredFlatWithControls

        // Build current flat sequence with control items at section
        // boundaries. The hidden and always-hidden control items are
        // filtered out of sectionItems even when findSection classifies
        // them into a section, because they are appended explicitly
        // after their respective sections below. Without this filter
        // each divider would appear twice in currentFlat (once via the
        // section iteration, once via the explicit append), causing
        // planFullSortSequence's early-return check to fail against a
        // single-divider desiredFiltered and the notched full-sort
        // path to regenerate the entire sequence every cycle.
        var currentFlat = [String]()
        for sectionName in [MenuBarSection.Name.visible, .hidden, .alwaysHidden] {
            let sectionItems = items.filter { item in
                guard isProfileItem(item) else { return false }
                let uid = item.uniqueIdentifier
                guard uid != hiddenCtrlUID && uid != ahCtrlUID else { return false }
                return sectionByWindowID[item.windowID] == sectionName
            }
            MenuBarItemManager.diagLog.debug(
                "applyProfileLayout: current \(sectionName.logString) has \(sectionItems.count) items: \(sectionItems.map(\.uniqueIdentifier))"
            )
            currentFlat.append(contentsOf: sectionItems.map(\.uniqueIdentifier))
            if sectionName == .visible {
                currentFlat.append(hiddenCtrlUID)
            } else if sectionName == .hidden, let ahCtrlUID {
                currentFlat.append(ahCtrlUID)
            }
        }

        // Filter desired sequence to only items present in the current bar.
        let currentSet = Set(currentFlat)
        var desiredFiltered = desiredFlat.filter { currentSet.contains($0) }

        // MARK: Phase 3: place unmanaged items via planUnmanagedPlacement
        // Items present in the menu bar but not in the profile are
        // placed via planUnmanagedPlacement. The planner consults the
        // user's saved layout history first (so a previously-seen app
        // returns to where the user last had it) and falls back to the
        // NewItemsPlacement preference for never-seen items. This
        // replaces the older hardcoded "park all unmanaged at visible-
        // leftmost" behavior.
        let visibleCtrlUID = items.first(where: { $0.tag == .visibleControlItem })?.uniqueIdentifier
        let desiredSet = Set(desiredFiltered)
        let unmanagedUIDs = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: currentFlat,
            desiredUIDs: desiredSet,
            hiddenCtrlUID: hiddenCtrlUID,
            ahCtrlUID: ahCtrlUID,
            visibleCtrlUID: visibleCtrlUID
        )
        if !unmanagedUIDs.isEmpty {
            // Build a DesiredLayout for the profile-apply context: the
            // saved layout is the source of truth for previously-seen
            // items; NewItemsPlacement is the fallback for unseen ones.
            // Pinning is left empty here because this code path only
            // positions unmanaged items, not the profile spec items.
            let desiredForUnmanaged = DesiredLayout.fromSavedSectionOrder(
                savedSectionOrder,
                newItemsPlacement: newItemsPlacement
            )
            let placements = LayoutReconciler.unmanagedPlacementPlan(
                desired: desiredForUnmanaged,
                unmanagedUIDs: unmanagedUIDs,
                currentUIDs: Set(currentFlat)
            )

            // Per-uid decision trace. Shows which item was deemed
            // unmanaged and which placement strategy fired. Cheap
            // (only logs when unmanaged items exist) and the most
            // direct signal for triaging "why did X move?" reports.
            for uid in unmanagedUIDs {
                let placementSummary: String
                switch placements[uid] {
                case let .saved(section, index)?:
                    placementSummary = "saved(section=\(section.logString), index=\(index))"
                case let .newItemAnchored(section, anchorUID, relation)?:
                    placementSummary = "newItemAnchored(section=\(section.logString), anchor=\(anchorUID), relation=\(String(describing: relation)))"
                case let .newItemDefault(section)?:
                    placementSummary = "newItemDefault(section=\(section.logString))"
                case nil:
                    placementSummary = "<no placement returned>"
                }
                MenuBarItemManager.diagLog.debug(
                    "Profile layout: planUnmanagedPlacement \(uid) -> \(placementSummary)"
                )
            }

            let applied = LayoutReconciler.applyUnmanagedPlacementsToDesired(
                placements: placements,
                unmanagedUIDs: unmanagedUIDs,
                desiredFiltered: desiredFiltered,
                sectionMap: sectionMap,
                savedSectionOrder: savedSectionOrder,
                controlUIDs: ControlUIDs(
                    visible: visibleCtrlUID,
                    hidden: hiddenCtrlUID,
                    alwaysHidden: ahCtrlUID
                )
            )
            desiredFiltered = applied.desiredFiltered
            sectionMap = applied.sectionMap

            MenuBarItemManager.diagLog.debug(
                "Profile layout: \(unmanagedUIDs.count) unmanaged item(s) placed via planUnmanagedPlacement"
            )
        }

        // MARK: Phase 4: notch overflow rebalance
        // On notched displays, calculate available visible space and overflow
        // items that won't fit into the hidden section. The Thaw visible
        // control icon stays as the last visible item (nearest the hidden divider).
        // Gated by the user-facing "Enable menu bar item overflow" toggle in
        // Advanced Settings; when off, the saved profile layout is honoured
        // verbatim and items the notch would otherwise eject stay in visible.
        let activeScreen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        if appState.settings.advanced.enableMenuBarItemOverflow,
           let screen = activeScreen,
           screen.hasNotch,
           let notch = screen.frameOfNotch
        {
            let notchGap = MenuBarSection.notchGap
            // Available space: from notch gap to Control Center's left edge.
            let ccItem = items.first(where: { $0.tag == .controlCenter })
            let rightBoundary = ccItem.map(\.bounds.minX) ?? screen.frame.maxX
            var availableWidth = rightBoundary - (notch.maxX + notchGap)

            // NSStatusItemSpacing is recorded here for diagnostic logging
            // only. macOS bakes the spacing into each status item's frame
            // (verified empirically: item.bounds.width grows 1:1 with the
            // spacing value), so item.bounds.width and the Control Center
            // item's bounds.minX already account for it. Subtracting a
            // separate (count - 1) * spacing gap here used to double-count
            // the spacing and ejected items into hidden when the bar still
            // had room, most visibly at the macOS default of 16.
            let userSpacing = CGFloat(max(0, 16 + appState.spacingManager.offset))

            // Subtract the layout footprint of items that occupy the
            // visible area but are not profile items: the Clock /
            // date-time display, BentoBox tray on systems that have
            // it, and any immovable accessibility extras. They take
            // real estate in the same way profile items do but are
            // filtered out of visibleUIDs below and would otherwise be
            // invisible to the budget check.
            // Transient system indicators (screen-recording AudioVideoModule,
            // FaceTime call indicator, ScreenCaptureUI overlay) appear and
            // disappear based on system events. Excluding them from the
            // budget keeps the overflow decision tied to the user's
            // permanent layout; otherwise, applying a profile while a
            // recording or call indicator is showing temporarily forces
            // a profile item out of visible, and that item won't come
            // back when the indicator goes away.
            let transientTags: [MenuBarItemTag] = [
                .audioVideoModule,
                .faceTime,
                .screenCaptureUI,
                .gameMode,
            ]
            var nonProfileFootprint: CGFloat = 0
            var nonProfileCount = 0
            var nonProfileBreakdown = [String]()
            for item in items where !isProfileItem(item) {
                guard item.bounds.minX >= notch.maxX,
                      item.bounds.maxX <= rightBoundary
                else { continue }
                if transientTags.contains(where: {
                    $0.namespace == item.tag.namespace && $0.title == item.tag.title
                }) || item.isTransientControlCenterItem {
                    continue
                }
                nonProfileFootprint += item.bounds.width
                nonProfileCount += 1
                nonProfileBreakdown.append("\(item.uniqueIdentifier)=\(item.bounds.width)")
            }
            availableWidth -= nonProfileFootprint

            // Measure visible item widths from current bounds.
            let visibleUIDs = Array(desiredFiltered.prefix(while: { $0 != hiddenCtrlUID }))
            var uidWidths = [String: CGFloat]()
            for uid in visibleUIDs {
                if let item = items.first(where: { $0.uniqueIdentifier == uid && isProfileItem($0) }) {
                    uidWidths[uid] = item.bounds.width
                }
            }

            // Find the Thaw visible control icon, which must always stay visible.
            let visibleCtrlUID = items.first(where: { $0.tag == .visibleControlItem })?.uniqueIdentifier

            var chevronFootprint: CGFloat = 0
            if let visibleCtrlUID,
               let chevron = items.first(where: { $0.uniqueIdentifier == visibleCtrlUID }),
               chevron.bounds.minX >= notch.maxX,
               chevron.bounds.maxX <= rightBoundary
            {
                chevronFootprint = chevron.bounds.width
                availableWidth -= chevronFootprint
            }

            MenuBarItemManager.diagLog.debug(
                """
                Notch overflow budget: screen.maxX=\(screen.frame.maxX) notch=[\(notch.minX)…\(notch.maxX)] \
                rightBoundary=\(rightBoundary) availableWidth=\(availableWidth) userSpacing=\(userSpacing) \
                visibleUIDs.count=\(visibleUIDs.count) \
                nonProfileCount=\(nonProfileCount) nonProfileFootprint=\(nonProfileFootprint) \
                chevronFootprint=\(chevronFootprint) \
                nonProfileBreakdown=[\(nonProfileBreakdown.joined(separator: ", "))]
                """
            )

            let overflowResult = LayoutSolver.planNotchOverflow(
                desiredFiltered: desiredFiltered,
                unmanagedUIDs: unmanagedUIDs,
                controlUIDs: ControlUIDs(
                    visible: visibleCtrlUID,
                    hidden: hiddenCtrlUID,
                    alwaysHidden: ahCtrlUID
                ),
                sectionMap: sectionMap,
                uidWidths: uidWidths,
                availableWidth: availableWidth
            )

            if !overflowResult.overflowUIDs.isEmpty {
                MenuBarItemManager.diagLog.info(
                    "Profile layout: notch overflow; \(overflowResult.overflowUIDs.count) item(s) moved from visible to hidden"
                )
                desiredFiltered = overflowResult.updatedDesiredFiltered
                sectionMap = overflowResult.updatedSectionMap
            }
        }

        // MARK: Phase 5: choose execution strategy (full-sort vs LCS)
        // On notched displays, use a full-section rearrange instead of
        // LCS-based partial moves. LCS leaves "stable" anchors in place,
        // but on notched screens those anchors may sit in or near the
        // notch dead zone, causing subsequent relative moves to fail.
        // A full rearrange places every item explicitly, section by
        // section, using the control items as the starting anchor.
        let useLCSOnNotched = appState.settings.advanced.useLCSSortingOnNotchedDisplays
        let isNotchedDisplay = activeScreen?.hasNotch == true && !useLCSOnNotched

        // Hide cursor for the entire profile apply to avoid visual jitter.
        let savedCursorPosition = NSEvent.mouseLocation
        MouseHelpers.hideCursor(watchdogTimeout: .seconds(30))
        defer { MouseHelpers.showCursor() }

        if isNotchedDisplay {
            // MARK: Phase 6a: full-sort execution (notched)
            let fullSequence = LayoutSolver.planFullSortSequence(
                currentFlat: currentFlat,
                desiredFiltered: desiredFiltered,
                sectionMap: sectionMap,
                hiddenCtrlUID: controlItems.hidden.uniqueIdentifier,
                ahCtrlUID: controlItems.alwaysHidden?.uniqueIdentifier
            )
            if fullSequence.isEmpty {
                MenuBarItemManager.diagLog.info("Profile layout (full sort): current order matches desired, skipping")
                updateProfileSortedSnapshot(source: source, items: items)
                persistProfileStateOnSuccess(source: source)
                scheduleDeferredCacheRefresh()
                return
            }

            let hiddenCtrlUID = controlItems.hidden.uniqueIdentifier
            let ahCtrlUID = controlItems.alwaysHidden?.uniqueIdentifier

            MenuBarItemManager.diagLog.info(
                "Profile layout (full sort): \(fullSequence.count) item(s) including controls"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout (full sort): sequence = \(fullSequence)"
            )

            var movedCount = 0

            // Every item (including control items) is placed
            // `.leftOfItem(controlCenter)`. Processing left-to-right,
            // each insertion pushes all previous items further left.
            // The last item placed (rightmost visible) ends up nearest
            // Control Center. Control items land in their correct
            // positions between sections naturally.
            for uid in fullSequence {
                guard !Task.isCancelled else { break }

                let freshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)

                let isControlUID = uid == hiddenCtrlUID || uid == ahCtrlUID
                guard let item = freshItems.first(where: {
                    if isControlUID { return $0.uniqueIdentifier == uid }
                    return $0.uniqueIdentifier == uid && isProfileItem($0)
                }) else {
                    MenuBarItemManager.diagLog.debug("Profile layout (full sort): \(uid) not found, skipping")
                    continue
                }

                guard let cc = freshItems.first(where: { $0.tag == .controlCenter }) else {
                    MenuBarItemManager.diagLog.error("Profile layout (full sort): Control Center not found")
                    break
                }

                let dest: MoveDestination = .leftOfItem(cc)
                MenuBarItemManager.diagLog.debug("Profile layout (full sort): \(uid) → .leftOfItem(CC)")

                do {
                    try await move(item: item, to: dest, skipInputPause: true)
                    movedCount += 1
                    try? await Task.sleep(for: .milliseconds(200))
                } catch {
                    MenuBarItemManager.diagLog.error("Profile layout (full sort): failed \(uid): \(error)")
                }
            }

            MenuBarItemManager.diagLog.info("Profile layout (full sort): completed with \(movedCount) move(s)")

            // Give macOS a moment to finalize positions before restoring
            // control item widths.
            try? await Task.sleep(for: .milliseconds(200))

            // Restore control items to their normal hiding state. The
            // control items are now at their correct positions between
            // sections, so expanding them to 10000px will push items to
            // their left off-screen, effectively hiding them.
            for section in appState.menuBarManager.sections {
                section.desiredState = .hideSection
                section.controlItem.state = .hideSection
            }

            // Give macOS time to process the control item expansion.
            try? await Task.sleep(for: .milliseconds(200))
        } else {
            // MARK: Phase 6b: LCS execution (non-notched)
            // ── Sub-phase 1: Move control items to optimal boundary positions ──
            //
            // Moving a control item reassigns all items on either side to
            // different sections in a single move. Calculate whether moving
            // a control item is cheaper than moving individual items.
            var movedCount = 0

            // Classify items into the two sets Phase 1 actually consults.
            // Read from the sectionByWindowID snapshot built earlier so the
            // classification here matches what the cache-log loop reported
            // above. Calling context.findSection again can return different
            // values for the same windowID if section.show()'s control-item
            // moves landed in between, which surfaces as an empty Phase 1
            // view of currently-occupied hidden / always-hidden sections.
            var currentHiddenSet = Set<String>()
            var currentAHSet = Set<String>()
            for item in items where isProfileItem(item) {
                switch sectionByWindowID[item.windowID] {
                case .hidden:
                    currentHiddenSet.insert(item.uniqueIdentifier)
                case .alwaysHidden:
                    currentAHSet.insert(item.uniqueIdentifier)
                case .visible, nil:
                    break
                }
            }

            let desiredHiddenSet = Set(itemOrder["hidden"] ?? [])
            let desiredAHSet = Set(itemOrder["alwaysHidden"] ?? [])

            // Check if AH_ctrl needs to move: items changing between hidden↔alwaysHidden.
            let wrongInHidden = currentHiddenSet.subtracting(desiredHiddenSet).intersection(desiredAHSet)
            let wrongInAH = currentAHSet.subtracting(desiredAHSet).intersection(desiredHiddenSet)
            let crossSectionMoves = wrongInHidden.count + wrongInAH.count

            // Items that are in always-hidden currently but should be in
            // hidden per the profile (or vice versa), regardless of whether
            // they appear in BOTH desired sets. The previous
            // crossSectionMoves tally only counts items present in the
            // *opposite* desired section, which is too narrow: when the
            // profile has empty hidden/always-hidden, or when items have
            // simply drifted out of one section without an explicit
            // counterpart, the AH_ctrl move is still the right answer
            // because it's a single move that fixes the section boundary
            // for everything it crosses.
            let needsHiddenMove = currentAHSet.intersection(desiredHiddenSet)
            let needsAHMove = currentHiddenSet.intersection(desiredAHSet)
            let totalSectionMismatch = needsHiddenMove.count + needsAHMove.count

            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: ahCtrlUID=\(ahCtrlUID ?? "nil"), crossSectionMoves=\(crossSectionMoves), totalSectionMismatch=\(totalSectionMismatch)"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: currentHidden=\(currentHiddenSet.sorted())"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: currentAH=\(currentAHSet.sorted())"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: desiredHidden=\(desiredHiddenSet.sorted())"
            )
            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: desiredAH=\(desiredAHSet.sorted())"
            )

            if crossSectionMoves > 0 || totalSectionMismatch > 0, let ahCtrlUID {
                // Moving AH_ctrl to the correct position is 1 move that
                // fixes all hidden↔alwaysHidden assignments.
                MenuBarItemManager.diagLog.debug(
                    "Profile layout: \(crossSectionMoves) items would change hidden↔alwaysHidden, moving AH_ctrl instead"
                )

                let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)

                // Place AH_ctrl so that desired hidden items are to its
                // RIGHT and desired AH items are to its LEFT (screen coords).
                //
                // Anchor to the first desired hidden item (rightmost in
                // screen coords = index 0 in profile order). Place AH_ctrl
                // .leftOfItem(firstHidden) so it sits between the hidden
                // items and the AH items.
                //
                // If hidden is empty, AH_ctrl goes next to H_ctrl.
                // If AH is empty, AH_ctrl also goes next to H_ctrl (no
                // boundary needed).
                let desiredHiddenUIDs = itemOrder["hidden"] ?? []
                if let ahItem = allFreshItems.first(where: { $0.uniqueIdentifier == ahCtrlUID }) {
                    let dest: MoveDestination? = if let firstHiddenUID = desiredHiddenUIDs.first,
                                                    let firstHidden = allFreshItems.first(where: { $0.uniqueIdentifier == firstHiddenUID && $0.isMovable })
                    {
                        // Place AH_ctrl to the LEFT of the rightmost hidden
                        // item. This puts AH_ctrl between AH items and
                        // hidden items.
                        .leftOfItem(firstHidden)
                    } else if let hItem = allFreshItems.first(where: { $0.uniqueIdentifier == hiddenCtrlUID }) {
                        // Hidden is empty; AH_ctrl goes next to H_ctrl.
                        .leftOfItem(hItem)
                    } else {
                        nil
                    }

                    if let dest, !Task.isCancelled {
                        MenuBarItemManager.diagLog.debug("Profile layout: moving AH_ctrl → \(dest.logString)")
                        do {
                            try await move(item: ahItem, to: dest, skipInputPause: true)
                            movedCount += 1
                            try? await Task.sleep(for: .milliseconds(200))
                        } catch {
                            MenuBarItemManager.diagLog.error("Profile layout: failed to move AH_ctrl: \(error)")
                        }
                    }
                }

                // Per-item cross-section fallback. The AH_ctrl move only
                // re-classifies items implicitly via its X position. When
                // the items destined for AH are currently RIGHT of items
                // destined for hidden (and vice versa); most commonly
                // after a fresh start where every managed item sits in
                // the hidden section; no single AH_ctrl placement can
                // split the two groups correctly. The move() no-op guard
                // can also cancel the AH_ctrl move outright when AH_ctrl
                // already sits adjacent to the chosen anchor. Either way,
                // a re-classification pass after the AH_ctrl attempt
                // tells us which items still need to cross the boundary,
                // and dragging them explicitly to .leftOfItem(AH_ctrl)
                // or .rightOfItem(AH_ctrl) puts them on the correct
                // side. The LCS within-section reorder pass below
                // handles intra-section ordering.
                let freshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                var freshItemsCopy = freshItems
                if let freshControl = ControlItemPair(
                    items: &freshItemsCopy,
                    hiddenControlItemWindowID: hiddenWID,
                    alwaysHiddenControlItemWindowID: alwaysHiddenWID
                ),
                    let ahItem = freshItems.first(where: { $0.uniqueIdentifier == ahCtrlUID })
                {
                    var verifyContext = CacheContext(
                        controlItems: freshControl,
                        displayID: Bridging.getActiveMenuBarDisplayID()
                    )
                    // Single classification pass, indexed by windowID so
                    // multi-display duplicates of the same uniqueIdentifier
                    // each keep their own section.
                    var postSectionByWindowID: [CGWindowID: MenuBarSection.Name] = [:]
                    for item in freshItems where isProfileItem(item) {
                        if let s = verifyContext.findSection(for: item) {
                            postSectionByWindowID[item.windowID] = s
                        }
                    }
                    var stillInHidden = Set<String>()
                    var stillInAH = Set<String>()
                    for item in freshItems where isProfileItem(item) {
                        switch postSectionByWindowID[item.windowID] {
                        case .hidden:
                            stillInHidden.insert(item.uniqueIdentifier)
                        case .alwaysHidden:
                            stillInAH.insert(item.uniqueIdentifier)
                        case .visible, .none:
                            break
                        }
                    }
                    let crossToAH = stillInHidden.intersection(desiredAHSet)
                    let crossToHidden = stillInAH.intersection(desiredHiddenSet)

                    if !crossToAH.isEmpty || !crossToHidden.isEmpty {
                        MenuBarItemManager.diagLog.debug(
                            "Profile layout: AH_ctrl placement left \(crossToAH.count) item(s) needing AH and \(crossToHidden.count) item(s) needing hidden, running per-item fallback"
                        )

                        // Move items destined for AH (currently in hidden)
                        // to the LEFT of AH_ctrl. Iterate in reverse
                        // profile order so the first item in
                        // itemOrder["alwaysHidden"] (rightmost in AH per
                        // profile convention, index 0) is moved last and
                        // therefore lands closest to AH_ctrl, matching
                        // the order LCS will leave it in.
                        let ahProfileOrder = itemOrder["alwaysHidden"] ?? []
                        let orderedCrossToAH = ahProfileOrder.reversed().filter { crossToAH.contains($0) }
                            + crossToAH.subtracting(ahProfileOrder).sorted()
                        for uid in orderedCrossToAH {
                            guard !Task.isCancelled else { break }
                            guard
                                let item = freshItems.first(where: { $0.uniqueIdentifier == uid && isProfileItem($0) })
                            else { continue }
                            do {
                                try await move(item: item, to: .leftOfItem(ahItem), skipInputPause: true)
                                movedCount += 1
                                try? await Task.sleep(for: .milliseconds(100))
                            } catch {
                                MenuBarItemManager.diagLog.error(
                                    "Profile layout: per-item move to AH failed for \(uid): \(error)"
                                )
                            }
                        }

                        // Move items destined for hidden (currently in AH)
                        // to the RIGHT of AH_ctrl. Iterate in profile
                        // order so itemOrder["hidden"] index 0 (rightmost
                        // in hidden = furthest from AH_ctrl) is moved
                        // first and gets pushed furthest right by
                        // subsequent moves.
                        let hiddenProfileOrder = itemOrder["hidden"] ?? []
                        let orderedCrossToHidden = hiddenProfileOrder.filter { crossToHidden.contains($0) }
                            + crossToHidden.subtracting(hiddenProfileOrder).sorted()
                        for uid in orderedCrossToHidden {
                            guard !Task.isCancelled else { break }
                            guard
                                let item = freshItems.first(where: { $0.uniqueIdentifier == uid && isProfileItem($0) })
                            else { continue }
                            do {
                                try await move(item: item, to: .rightOfItem(ahItem), skipInputPause: true)
                                movedCount += 1
                                try? await Task.sleep(for: .milliseconds(100))
                            } catch {
                                MenuBarItemManager.diagLog.error(
                                    "Profile layout: per-item move to hidden failed for \(uid): \(error)"
                                )
                            }
                        }
                    }
                }
            }

            // ── Sub-phase 2: LCS for remaining item ordering ──
            //
            // Re-fetch items and rebuild sequences after control item moves
            // may have changed section assignments.
            if movedCount > 0 {
                // Re-fetch items and rebuild section assignments after
                // the control item move changed section boundaries.
                items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                var itemsCopy2 = items
                guard let freshControl = ControlItemPair(
                    items: &itemsCopy2,
                    hiddenControlItemWindowID: hiddenWID,
                    alwaysHiddenControlItemWindowID: alwaysHiddenWID
                ) else {
                    MenuBarItemManager.diagLog.error("applyProfileLayout: lost control items after phase 1")
                    scheduleDeferredCacheRefresh()
                    return
                }

                var newContext = CacheContext(
                    controlItems: freshControl,
                    displayID: Bridging.getActiveMenuBarDisplayID()
                )

                currentFlat.removeAll()
                for sectionName in [MenuBarSection.Name.visible, .hidden, .alwaysHidden] {
                    let sectionItems = items.filter { item in
                        guard isProfileItem(item) else { return false }
                        return newContext.findSection(for: item) == sectionName
                    }
                    currentFlat.append(contentsOf: sectionItems.map(\.uniqueIdentifier))
                }
            }

            // Remove control items from sequences for LCS; they've been
            // handled in Phase 1. If Phase 1 moved a control item,
            // currentFlat was rebuilt so re-filter it.
            //
            // Source desiredFiltered (not desiredFlat): desiredFiltered
            // is the post-unmanaged-insert and post-notch-overflow
            // sequence. Using it lets the LCS planner consider
            // newly-detected items at their saved badge position
            // (so applying a profile relocates them to that spot
            // instead of leaving them wherever macOS detected them)
            // and respect notch-overflow's section reassignments.
            let currentNoControls = currentFlat.filter { $0 != hiddenCtrlUID && $0 != ahCtrlUID }
            let desiredNoControls = desiredFiltered.filter { $0 != hiddenCtrlUID && $0 != ahCtrlUID }
            let plannedMoves = LayoutSolver.planLCSMoveSequence(
                currentNoControls: currentNoControls,
                desiredNoControls: desiredNoControls,
                sectionMap: sectionMap
            )

            guard !plannedMoves.isEmpty else {
                if movedCount > 0 {
                    MenuBarItemManager.diagLog.info("Profile layout: completed with \(movedCount) control item move(s), no item reordering needed")
                } else {
                    MenuBarItemManager.diagLog.info("Profile layout: all items already in correct positions")
                }
                updateProfileSortedSnapshot(source: source, items: items)
                persistProfileStateOnSuccess(source: source)
                scheduleDeferredCacheRefresh()
                return
            }

            MenuBarItemManager.diagLog.info(
                "Profile layout: \(plannedMoves.count) item move(s) needed (\(movedCount) control move(s) preceded)"
            )

            for planned in plannedMoves {
                guard !Task.isCancelled else { break }

                let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                var freshItemsCopy = allFreshItems
                guard let freshControl = ControlItemPair(
                    items: &freshItemsCopy,
                    hiddenControlItemWindowID: hiddenWID,
                    alwaysHiddenControlItemWindowID: alwaysHiddenWID
                ) else {
                    break
                }

                guard let item = allFreshItems.first(where: {
                    $0.uniqueIdentifier == planned.uid && isProfileItem($0)
                }) else {
                    continue
                }

                // Resolve the abstract destination against fresh items.
                // If the anchor item is missing (e.g. it disappeared
                // mid-sequence), the reconciler falls back to the
                // section boundary for the planned uid's target
                // section.
                let fallbackSection = sectionName(for: sectionMap[planned.uid] ?? "visible") ?? .visible
                let dest = LayoutReconciler.resolveDestination(
                    planned.destination,
                    items: allFreshItems,
                    controlItems: freshControl,
                    fallbackSection: fallbackSection
                )

                do {
                    try await move(item: item, to: dest, skipInputPause: true)
                    movedCount += 1
                    try? await Task.sleep(for: .milliseconds(200))
                } catch {
                    MenuBarItemManager.diagLog.error(
                        "Profile layout: failed to move \(planned.uid): \(error)"
                    )
                }
            }

            MenuBarItemManager.diagLog.info("Profile layout: completed with \(movedCount) move(s)")
        }

        // MARK: Phase 7: finalize (cursor, snapshot, cache, UI refresh)
        // Restore cursor to its original position.
        let screen = NSScreen.screens.first(where: { $0.frame.contains(savedCursorPosition) })
            ?? NSScreen.main
        if let screen {
            let cgY = screen.frame.origin.y + screen.frame.height - savedCursorPosition.y
            MouseHelpers.warpCursor(to: CGPoint(x: savedCursorPosition.x, y: cgY))
        }

        // Re-fetch items after moves and update the snapshot so the
        // late-arrival detection doesn't re-trigger for items we just sorted.
        // Profile-only: the profile-sorted snapshot and
        // isApplyingProfileLayout flag are only meaningful when a
        // profile is active; the savedOrder source leaves them alone.
        items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        // Commit profile state to disk only if we weren't cancelled
        // mid-Phase-6. The in-loop cancellation guards break out of the
        // move loop but execution still flows into Phase 7; without
        // this check we'd persist a profile that was only partially
        // applied to the bar.
        if !Task.isCancelled {
            persistProfileStateOnSuccess(source: source)
        }
        clearProfileState(source: source, items: items)

        scheduleDeferredCacheRefresh()
    }

    /// Re-applies the user's saved menu-bar layout via the unified
    /// apply path. Builds the inputs that applyProfileLayout expects
    /// from savedSectionOrder and dispatches with source .savedOrder
    /// so the profile-only state arming (pinning
    /// overwrite, activeProfileLayout, isApplyingProfileLayout,
    /// late-arrival snapshot) is skipped while the shared discovery /
    /// unmanaged-placement / notch-overflow / execution machinery runs
    /// identically.
    ///
    /// Returns true if the bulk apply was dispatched (the body will
    /// drive its own follow-up cache cycle and the caller should not
    /// continue with the rest of its current cycle). Returns false
    /// when an entry guard rejects the call (no saved layout, profile
    /// apply in flight, cooldown active, no detected change to react
    /// to, no saved items currently present).
    /// Detects whether the current bar layout differs from
    /// `savedSectionOrder` in section membership. Returns true if any
    /// movable, hideable item whose baseID appears in the saved order
    /// is currently in a different section than where it was saved.
    ///
    /// Used as a secondary trigger for `applySavedLayout`: the windowID
    /// gate fires on app quit/relaunch, but ambient drift (third-party
    /// menu bar tools, Stage Manager toggles, macOS re-spawning the
    /// bar without churning windowIDs) leaves windowIDs intact while
    /// the layout drifts. This check catches that case so the bulk
    /// apply still reasserts the saved order.
    ///
    /// Lightweight by design: item bounds are read from the supplied
    /// items array (already populated by the caller's
    /// `getMenuBarItems` pass) rather than via per-item AX round-trips
    /// through `CacheContext`. Items that straddle a control-item
    /// boundary are ignored to avoid false positives during transient
    /// section show/hide animations. Multi-instance baseIDs use
    /// "last write wins" in the expected-section map; this can
    /// false-positive when a single app has instances split across
    /// sections in `savedSectionOrder`, but the bulk apply
    /// early-returns when no moves are needed, so the cost is minor.
    private func currentLayoutDivergesFromSaved(
        items: [MenuBarItem],
        controlItems: ControlItemPair
    ) -> Bool {
        var savedSectionByBaseID = [String: MenuBarSection.Name]()
        for (sectionKey, ids) in savedSectionOrder {
            guard let section = sectionName(for: sectionKey) else { continue }
            for id in ids {
                let parts = id.split(separator: ":", maxSplits: 2)
                let baseID = parts.prefix(2).joined(separator: ":")
                savedSectionByBaseID[baseID] = section
            }
        }
        guard !savedSectionByBaseID.isEmpty else { return false }

        let hiddenMinX = controlItems.hidden.bounds.minX
        let hiddenMaxX = controlItems.hidden.bounds.maxX
        let ahBounds = controlItems.alwaysHidden?.bounds

        for item in items where !item.isControlItem && item.canBeHidden && item.isMovable {
            let baseID = "\(item.tag.namespace):\(item.tag.title)"
            guard let expectedSection = savedSectionByBaseID[baseID] else {
                continue
            }

            let currentSection: MenuBarSection.Name?
            if item.bounds.minX >= hiddenMaxX {
                currentSection = .visible
            } else if let ahBounds, item.bounds.maxX <= ahBounds.minX {
                currentSection = .alwaysHidden
            } else if let ahBounds, item.bounds.minX >= ahBounds.maxX, item.bounds.maxX <= hiddenMinX {
                currentSection = .hidden
            } else if ahBounds == nil, item.bounds.maxX <= hiddenMinX {
                currentSection = .hidden
            } else {
                currentSection = nil
            }

            guard let currentSection else { continue }
            if currentSection != expectedSection {
                return true
            }
        }
        return false
    }

    func applySavedLayout(
        items: [MenuBarItem],
        previousWindowIDs: [CGWindowID],
        controlItems: ControlItemPair
    ) async -> Bool {
        // Each guard logs a distinct reason so a "Thaw stopped
        // restoring my layout" bug report can be diagnosed from the
        // first set of logs. Order is significant: the cheap state
        // checks run first; window-ID/tag inspection runs last so we
        // don't compute sets when an earlier guard would reject anyway.
        guard !savedSectionOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, savedSectionOrder is empty")
            return false
        }
        guard !suppressNextNewLeftmostItemRelocation else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, suppressNextNewLeftmostItemRelocation armed")
            return false
        }
        // applyProfileLayout owns the in-flight layout while it's
        // running; a concurrent savedOrder apply would fight it.
        guard !isApplyingProfileLayout else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, profile apply in flight")
            return false
        }
        // 5 s cooldown after a recent move (same value the legacy
        // restoreItemsToSavedSections used) prevents cascading
        // re-applies when many apps relaunch in quick succession.
        guard !lastMoveOperationOccurred(within: .seconds(5)) else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, within 5s move cooldown")
            return false
        }

        // Trigger detection. The cache cycle calls this on every tick;
        // without a change gate we would run a full bulk apply every
        // ~5 s indefinitely. Two independent signals advance past the
        // gate:
        //
        // 1. windowIDsChanged: a previous windowID is missing from the
        //    current set, i.e., an item disappeared. Covers app-quit
        //    and app-relaunch. Pure additions are owned by
        //    relocateNewLeftmostItems, not this path. WindowID
        //    recycling (same WID, different item) is uncovered.
        //    The previous-set-empty escape handles first-cycle startup
        //    where there's no prior frame to diff against.
        //
        // 2. layoutDiverged: at least one saved item is currently in a
        //    different section than savedSectionOrder records. Catches
        //    ambient drift (third-party tools repositioning icons,
        //    Stage Manager toggles, screen lock/unlock cycles, macOS
        //    re-spawning the bar) where windowIDs stay stable while
        //    sections shift. Also catches cold-boot for non-profile
        //    users, where the first cycle has previousWindowIDs empty
        //    but the bar is in macOS-default order rather than saved.
        //
        // Divergence is computed lazily: only consulted when
        // windowIDsChanged didn't already advance the gate, so the
        // happy path on app quit/relaunch pays nothing.
        let currentWindowIDSet = Set(items.map(\.windowID))
        let previousWindowIDSet = Set(previousWindowIDs)
        let windowIDsChanged = !previousWindowIDSet.isEmpty &&
            !previousWindowIDSet.isSubset(of: currentWindowIDSet)
        let layoutDiverged = windowIDsChanged
            ? false
            : currentLayoutDivergesFromSaved(items: items, controlItems: controlItems)
        guard windowIDsChanged || layoutDiverged else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no windowID change and saved layout matches current")
            return false
        }

        // Saved-tags intersection: skip if none of the saved items are
        // currently present. Matches the legacy restore's guard;
        // protects against running the bulk apply on a menu bar that
        // shares no widgets with the persisted layout.
        let currentTags = Set(items.map { "\($0.tag.namespace):\($0.tag.title)" })
        let savedTags = Set(savedSectionOrder.values.flatMap(\.self))
        guard !savedTags.isDisjoint(with: currentTags) else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no saved items currently present")
            return false
        }

        // Build itemSectionMap from savedSectionOrder. Each identifier
        // points back at its persisted section key.
        var itemSectionMap = [String: String]()
        for (sectionKey, identifiers) in savedSectionOrder {
            for identifier in identifiers {
                itemSectionMap[identifier] = sectionKey
            }
        }

        let trigger = windowIDsChanged ? "windowID change" : "layout divergence"
        MenuBarItemManager.diagLog.info("applySavedLayout: dispatching bulk apply (\(trigger))")

        // The shared body uses itemOrder as the per-section ordered
        // identifier list, which is structurally identical to
        // savedSectionOrder. Pass the saved order through unchanged.
        // Pinning is preserved from existing state, not derived from
        // savedSectionOrder (savedSectionOrder has no pinning concept).
        await applyProfileLayout(
            pinnedHidden: pinnedHiddenBundleIDs,
            pinnedAlwaysHidden: pinnedAlwaysHiddenBundleIDs,
            sectionOrder: savedSectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: savedSectionOrder,
            source: .savedOrder
        )
        return true
    }

    /// Restores items that are stuck in a "blocked" state (positioned at x=-1)
    /// back to the visible section. This is called when the app is terminating
    /// to prevent items from being permanently stuck in macOS's Control Center preferences.
    /// Only items at x=-1 are restored; normally hidden items are left as-is.
    ///
    /// - Returns: The number of items that failed to move.
    @MainActor
    func restoreBlockedItemsToVisible() async -> Int {
        MenuBarItemManager.diagLog.info("Checking for blocked items (x=-1) to restore before app termination")

        guard let appState else {
            MenuBarItemManager.diagLog.error("Cannot restore items: missing appState")
            return 0
        }

        // Get current items
        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        // Find items that are blocked (at x=-1)
        let blockedItems = items.filter { item in
            guard item.isMovable, !item.isControlItem else { return false }
            let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
            return bounds.origin.x == -1
        }

        guard !blockedItems.isEmpty else {
            MenuBarItemManager.diagLog.debug("No blocked items found - skipping restoration")
            return 0
        }

        MenuBarItemManager.diagLog.warning("Found \(blockedItems.count) blocked items at x=-1, attempting to restore")

        // Get window IDs from ControlItem objects
        let hiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        // Create ControlItemPair to get MenuBarItem representations
        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenWID
        ) else {
            MenuBarItemManager.diagLog.error("Cannot restore items: unable to find hidden control item")
            return blockedItems.count
        }

        var failedMoves = 0

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        // Move blocked items to the right of the hidden control item (visible section)
        for item in blockedItems {
            do {
                try await move(
                    item: item,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true,
                    watchdogTimeout: Self.layoutWatchdogTimeout
                )
                MenuBarItemManager.diagLog.info("Successfully restored blocked item \(item.logString) to visible section")
            } catch {
                failedMoves += 1
                MenuBarItemManager.diagLog.error("Failed to restore blocked item \(item.logString): \(error)")
            }
        }

        MenuBarItemManager.diagLog.info("Restore completed: \(blockedItems.count - failedMoves)/\(blockedItems.count) blocked items restored")

        // Give macOS a moment to settle
        try? await Task.sleep(for: .milliseconds(200))

        return failedMoves
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
        let (seconds, attoseconds) = components
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
