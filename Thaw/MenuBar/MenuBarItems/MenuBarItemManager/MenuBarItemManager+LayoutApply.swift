//
//  MenuBarItemManager+LayoutApply.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: Layout Reset

extension MenuBarItemManager {
    /// Tracks which move timestamp belongs to a multi-item automatic apply.
    ///
    /// After each move the batch adopts the timestamp it saw while holding
    /// moveGate, so it accepts its own moves and rejects a user move in between.
    nonisolated struct BatchMovePreflightState {
        private var didFinishMove = false
        private var expectedTimestamp: ContinuousClock.Instant?

        func shouldBeginMove(
            currentTimestamp: ContinuousClock.Instant?,
            initialPreflight: () -> Bool
        ) -> Bool {
            guard didFinishMove else {
                return initialPreflight()
            }
            return currentTimestamp == expectedTimestamp
        }

        mutating func recordMoveGateExit(timestamp: ContinuousClock.Instant?) {
            didFinishMove = true
            expectedTimestamp = timestamp
        }
    }

    /// Authority of a bulk layout request. Higher-authority work may replace
    /// lower-authority work; lower-authority background work never displaces a
    /// profile the user explicitly selected.
    nonisolated enum LayoutBatchKind: Int, Equatable {
        case savedRestore
        case profileResort
        case explicitProfile
    }

    nonisolated struct LayoutBatchLease: Equatable {
        let generation: UInt
        let kind: LayoutBatchKind
    }

    static nonisolated func layoutBatchMaySupersede(
        active: LayoutBatchKind?,
        requested: LayoutBatchKind
    ) -> Bool {
        guard let active else { return true }
        return requested.rawValue >= active.rawValue
    }

    /// Claims ownership for a batch and invalidates any lower-authority work.
    @discardableResult
    func beginLayoutBatch(_ kind: LayoutBatchKind) -> LayoutBatchLease? {
        guard Self.layoutBatchMaySupersede(
            active: activeLayoutBatchLease?.kind,
            requested: kind
        ) else {
            MenuBarItemManager.diagLog.debug(
                "Layout batch \(kind) deferred behind \(String(describing: activeLayoutBatchLease?.kind))"
            )
            return nil
        }

        if kind == .explicitProfile {
            profileResortTask?.cancel()
            profileResortTask = nil
        }
        layoutBatchGeneration &+= 1
        let lease = LayoutBatchLease(generation: layoutBatchGeneration, kind: kind)
        activeLayoutBatchLease = lease
        return lease
    }

    func layoutBatchIsCurrent(_ lease: LayoutBatchLease) -> Bool {
        activeLayoutBatchLease == lease && layoutBatchGeneration == lease.generation
    }

    func finishLayoutBatch(_ lease: LayoutBatchLease) {
        guard layoutBatchIsCurrent(lease) else { return }
        activeLayoutBatchLease = nil
    }

    func cancelActiveLayoutBatch(ifKind kind: LayoutBatchKind) {
        guard activeLayoutBatchLease?.kind == kind else { return }
        layoutBatchGeneration &+= 1
        activeLayoutBatchLease = nil
    }

    enum LayoutResetError: LocalizedError {
        case missingAppState
        case missingControlItems
        case alreadyInProgress

        var errorDescription: String? {
            switch self {
            case .missingAppState:
                "Unable to access app state"
            case .missingControlItems:
                "Couldn't find section dividers in the menu bar"
            case .alreadyInProgress:
                "A layout reset is already in progress"
            }
        }

        var recoverySuggestion: String? {
            "Make sure \(Constants.displayName) is running and try again."
        }
    }

    /// Resets layout data to a fresh-install state and moves every movable,
    /// hideable item except the Thaw icon to Hidden.
    ///
    /// - Returns: The number of items that failed to move.
    func resetLayoutToFreshState() async throws -> Int {
        try await resetLayout(to: .hidden)
    }

    /// Moves every movable, hideable item except the Thaw icon to Visible.
    func resetLayoutToVisible() async throws -> Int {
        try await resetLayout(to: .visible)
    }

    /// Moves every movable, hideable item except the Thaw icon to Always Hidden.
    func resetLayoutToAlwaysHidden() async throws -> Int {
        try await resetLayout(to: .alwaysHidden)
    }

    private func resetLayout(to target: LayoutResetTarget) async throws -> Int {
        guard !isResettingLayout else {
            MenuBarItemManager.diagLog.warning("resetLayout: already in progress, rejecting concurrent reset")
            throw LayoutResetError.alreadyInProgress
        }

        MenuBarItemManager.diagLog.info("Resetting menu bar layout to \(target.logString)")
        // A user reset is authoritative; settling would block the post-reset restore and save.
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

            // Nudge macOS to recreate the control items, then retry once.
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
                ), retryControlItems.canRepositionControlItems {
                    guard !target.requiresAlwaysHiddenDivider || retryControlItems.alwaysHidden != nil else {
                        throw LayoutResetError.missingControlItems
                    }
                    MenuBarItemManager.diagLog.info("Recovered hidden section control item after re-enabling always-hidden section")
                    prepareLayoutStateForReset()
                    _ = await enforceControlItemOrder(controlItems: retryControlItems)
                    return try await resetLayoutWithControlItems(
                        controlItems: retryControlItems,
                        items: items,
                        target: target
                    )
                }
            }

            throw LayoutResetError.missingControlItems
        }

        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.error(
                "Layout reset aborted: control items resolved only by provisional AX-frame correlation"
            )
            throw LayoutResetError.missingControlItems
        }
        guard !target.requiresAlwaysHiddenDivider || controlItems.alwaysHidden != nil else {
            MenuBarItemManager.diagLog.error(
                "Layout reset aborted: always-hidden section divider is unavailable"
            )
            throw LayoutResetError.missingControlItems
        }

        // A provisional divider lookup must leave the saved layout intact.
        prepareLayoutStateForReset()

        _ = await enforceControlItemOrder(controlItems: controlItems)

        return try await resetLayoutWithControlItems(
            controlItems: controlItems,
            items: items,
            target: target
        )
    }

    private func prepareLayoutStateForReset() {
        ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue] = 0
        ControlItemDefaults.resetChevronPositions()

        knownItemIdentifiers.removeAll()
        pinnedHiddenBundleIDs.removeAll()
        pinnedAlwaysHiddenBundleIDs.removeAll()
        pendingRelocations.removeAll()
        pendingReturnDestinations.removeAll()
        savedSectionOrder.removeAll()
        activeProfileLayout = nil
        activeProfileItemIdentifiers.removeAll()
        profileSortedItemIdentifiers.removeAll()
        profileResortTask?.cancel()
        profileResortTask = nil
        persistKnownItemIdentifiers()
        persistPinnedBundleIDs()
        persistPendingRelocations()
        persistSavedSectionOrder()
        // Old retirements would keep pruning identifiers from the rebuilt layout.
        staleIdentifierLedger.removeAll()
        temporarilyShownItemContexts.removeAll()

        newItemsPlacement = NewItemsPlacement.defaultValue
        Defaults.removeObject(forKey: .newItemsSection)
        Defaults.removeObject(forKey: .newItemsPlacementData)
        suppressNextNewLeftmostItemRelocation = true
    }

    private func resetLayoutWithControlItems(
        controlItems: ControlItemPair,
        items: [MenuBarItem],
        target: LayoutResetTarget
    ) async throws -> Int {
        guard let appState else {
            throw LayoutResetError.missingAppState
        }

        appState.menuBarManager.iceBarPanel.close()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        func destination(for controls: ControlItemPair) -> MoveDestination? {
            switch target {
            case .visible:
                .rightOfItem(controls.hidden)
            case .hidden:
                .leftOfItem(controls.hidden)
            case .alwaysHidden:
                controls.alwaysHidden.map(MoveDestination.leftOfItem)
            }
        }

        func itemsOutsideTarget(_ items: [MenuBarItem], controls: ControlItemPair) -> [MenuBarItem] {
            let hiddenBounds = Bridging.getWindowBounds(for: controls.hidden.windowID)
                ?? controls.hidden.bounds
            let alwaysHiddenBounds = controls.alwaysHidden.flatMap {
                Bridging.getWindowBounds(for: $0.windowID) ?? $0.bounds
            }
            return items.filter { item in
                guard item.isMovable, item.canBeHidden, !item.isControlItem,
                      item.tag != .visibleControlItem
                else {
                    return false
                }
                let itemBounds = item.liveBounds
                return !target.contains(
                    itemBounds: itemBounds,
                    hiddenBounds: hiddenBounds,
                    alwaysHiddenBounds: alwaysHiddenBounds
                )
            }
        }

        func movePass(_ items: [MenuBarItem], controls: ControlItemPair) async -> Int {
            guard let destination = destination(for: controls) else {
                return items.count
            }
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
                        to: destination,
                        skipInputPause: true,
                        options: .init(watchdogTimeout: Self.layoutWatchdogTimeout)
                    )
                } catch {
                    failed += 1
                    MenuBarItemManager.diagLog.error("Failed to move \(item.logString) during layout reset: \(error)")
                }
            }
            return failed
        }

        let firstPassItems = target.movesAllCandidatesInFirstPass
            ? items
            : itemsOutsideTarget(items, controls: controlItems)
        _ = await movePass(firstPassItems, controls: controlItems)

        try? await Task.sleep(for: .milliseconds(200))

        var refreshedItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedMoves = 0
        let refreshHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let refreshAlwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        guard let refreshedControls = ControlItemPair(
            items: &refreshedItems,
            hiddenControlItemWindowID: refreshHiddenWID,
            alwaysHiddenControlItemWindowID: refreshAlwaysHiddenWID
        ), refreshedControls.canRepositionControlItems,
        !target.requiresAlwaysHiddenDivider || refreshedControls.alwaysHidden != nil
        else {
            MenuBarItemManager.diagLog.error(
                "Layout reset aborted before pass 2: authoritative section dividers are unavailable"
            )
            throw LayoutResetError.missingControlItems
        }

        let notYetInTarget = itemsOutsideTarget(refreshedItems, controls: refreshedControls)
        if !notYetInTarget.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "Layout reset pass 2: \(notYetInTarget.count) items not yet in \(target.logString)"
            )
            failedMoves = await movePass(notYetInTarget, controls: refreshedControls)
        }

        cacheActor.clearCachedItemWindowIDs()
        itemCache = ItemCache(displayID: nil)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let token = self.addBackgroundCacheWaiter(continuation)
            Task { [weak self] in
                await self?.cacheItemsRegardless(skipRecentMoveCheck: true, waiterToken: token)
            }
            // Watchdog: the cache call can bail before the gate or its nested recache
            // may never run. Whoever removes the token first resumes.
            Task { [weak self] in
                try? await Task.sleep(for: MenuBarItemManager.layoutWatchdogTimeout)
                guard let self, self.backgroundCacheWaiters[token] != nil else { return }
                MenuBarItemManager.diagLog.warning(
                    "resetLayout: background cache wait timed out after \(MenuBarItemManager.layoutWatchdogTimeout); resuming via watchdog"
                )
                self.resumeBackgroundCacheWaiter(token)
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

        // Clears a -1 sentinel cached while the menu bar window was unavailable mid-reset.
        NSScreen.invalidateMenuBarHeightCache()

        return failedMoves
    }

    /// Ends a pre-flighted settling period when a spacing apply relaunched nothing.
    ///
    /// Won't cancel one promoted by a real relaunch wave, or a duplicate
    /// screenParametersChanged would run applyProfileLayout on a half-populated cache.
    func cancelSettlingPeriod(reason: String) {
        guard isInStartupSettling || startupSettlingTask != nil else { return }
        if !settlingExpectedBundleIDs.isEmpty {
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling cancel ignored; \(settlingExpectedBundleIDs.count) expected bundle ID(s) still pending"
            )
            return
        }
        // Cold-boot settling stays: many apps haven't reattached yet.
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

    /// Debounced re-apply of the active profile to place late-arriving items.
    func scheduleProfileResort() {
        profileResortTask?.cancel()
        guard let lease = beginLayoutBatch(.profileResort) else { return }
        profileResortTask = Task { [weak self] in
            defer {
                if let self {
                    if self.layoutBatchIsCurrent(lease) {
                        self.profileResortTask = nil
                    }
                    self.finishLayoutBatch(lease)
                }
            }
            // Short: the app-launch notification is already debounced 1 s.
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return // Cancelled; a newer schedule replaced us.
            }
            guard let self, let layout = self.activeProfileLayout else { return }
            guard self.layoutBatchIsCurrent(lease) else { return }
            guard !self.isInStartupSettling else { return }
            guard !self.isRestoringItemOrder else { return }

            // Same gate as applySavedLayout, or a bar whose batches never finish
            // re-sorts on every late arrival (#899). applyProfile doesn't come through here.
            guard self.isAutomaticBulkApplyPermitted(caller: "Profile re-sort") else {
                return
            }

            MenuBarItemManager.diagLog.info("Profile re-sort: re-applying layout for late-arriving items")
            await self.applyProfileLayout(
                ProfileLayoutSpec(
                    pinnedHidden: layout.pinnedHidden,
                    pinnedAlwaysHidden: layout.pinnedAlwaysHidden,
                    sectionOrder: layout.sectionOrder,
                    itemSectionMap: layout.itemSectionMap,
                    itemOrder: layout.itemOrder
                ),
                automatic: true,
                shouldBegin: {
                    self.layoutBatchIsCurrent(lease)
                }
            )
        }
    }

    /// Also stops any pending late-arrival re-sort.
    func clearActiveProfileLayout() {
        activeProfileLayout = nil
        activeProfileItemIdentifiers.removeAll()
        profileSortedItemIdentifiers.removeAll()
        profileResortTask?.cancel()
        profileResortTask = nil
        cancelActiveLayoutBatch(ifKind: .profileResort)
        isApplyingProfileLayout = false
    }

    /// Awaits the end of the startup settling window before returning.
    ///
    /// Loops because performSetup can re-enter mid-await and start a new window.
    private func waitForStartupSettlingToEnd() async {
        while isInStartupSettling {
            guard let settlingTask = startupSettlingTask else { break }
            MenuBarItemManager.diagLog.debug(
                "applyProfileLayout: waiting for startup settling to end"
            )
            await settlingTask.value
        }
    }

    /// The pinning sets, per-section order, and the two identifier maps derived
    /// from it, which every apply carries together.
    nonisolated struct ProfileLayoutSpec {
        let pinnedHidden: Set<String>
        let pinnedAlwaysHidden: Set<String>
        let sectionOrder: [String: [String]]
        let itemSectionMap: [String: String]
        let itemOrder: [String: [String]]
    }

    /// Decides which state an apply arms and clears; the body is the same.
    ///
    /// - profile: the spec overwrites savedSectionOrder, pinning, and
    ///   activeProfileLayout; isApplyingProfileLayout gates concurrent restores.
    /// - savedOrder: savedSectionOrder is already the truth and pinning is
    ///   kept. Only isRestoringItemOrder is armed.
    enum ApplySource {
        case profile
        case savedOrder
    }

    /// Arms in-memory profile state and the in-flight gate. No-op for .savedOrder.
    ///
    /// Disk writes wait for persistProfileStateOnSuccess, so an aborted apply
    /// leaves the previous profile on disk.
    func armProfileState(
        source: ApplySource,
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) {
        guard case .profile = source else { return }

        // Snapshot for rollback on cancel. The token stops a displaced apply
        // from restoring over a newer one.
        profileApplyToken &+= 1
        priorProfileApplySnapshot = ProfileApplySnapshot(
            token: profileApplyToken,
            pinnedHidden: pinnedHiddenBundleIDs,
            pinnedAlwaysHidden: pinnedAlwaysHiddenBundleIDs,
            sectionOrder: savedSectionOrder,
            profileLayout: activeProfileLayout,
            profileItemIdentifiers: activeProfileItemIdentifiers
        )

        pinnedHiddenBundleIDs = pinnedHidden
        pinnedAlwaysHiddenBundleIDs = pinnedAlwaysHidden
        savedSectionOrder = sectionOrder

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

    /// Rolls back after a cancelled apply, only if no newer apply has bumped the token.
    private func restoreProfileStateAfterAbortedApply(token: Int) {
        guard token == profileApplyToken,
              let snapshot = priorProfileApplySnapshot,
              snapshot.token == token
        else {
            MenuBarItemManager.diagLog.debug(
                "applyProfileLayout: cancelled apply no longer owns the armed profile state, skipping rollback"
            )
            return
        }
        pinnedHiddenBundleIDs = snapshot.pinnedHidden
        pinnedAlwaysHiddenBundleIDs = snapshot.pinnedAlwaysHidden
        savedSectionOrder = snapshot.sectionOrder
        activeProfileLayout = snapshot.profileLayout
        activeProfileItemIdentifiers = snapshot.profileItemIdentifiers
        priorProfileApplySnapshot = nil
        isApplyingProfileLayout = false
        MenuBarItemManager.diagLog.info(
            "applyProfileLayout: aborted apply rolled back in-memory profile state to the last committed profile"
        )
    }

    /// Syncs activeProfileLayout after the user updates the active profile, with
    /// no moves. Otherwise the next late-arrival re-sort reverts to the old spec.
    ///
    /// Touches nothing else: no saved order, pinning, in-flight flag, or re-sort.
    func rearmActiveProfileLayout(
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) {
        activeProfileLayout = (
            pinnedHidden: pinnedHidden,
            pinnedAlwaysHidden: pinnedAlwaysHidden,
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )
        activeProfileItemIdentifiers = Set(itemOrder.values.flatMap(\.self))
        MenuBarItemManager.diagLog.debug(
            "rearmActiveProfileLayout: refreshed cached profile spec after active-profile update (\(self.activeProfileItemIdentifiers.count) item identifiers)"
        )
    }

    /// Collects the control-item bounds the divider-order gate compares.
    ///
    /// nil for a divider that is absent from the reading; the order gate
    /// treats absence as unverifiable rather than as a violation.
    private func dividerControlItemBounds(
        items: [MenuBarItem],
        controlItems: ControlItemPair
    ) -> (visible: CGRect?, hidden: CGRect, alwaysHidden: CGRect?) {
        let visible = items
            .first { $0.tag == .visibleControlItem }?
            .bounds
        return (visible, controlItems.hidden.bounds, controlItems.alwaysHidden?.bounds)
    }

    /// Lets a stranded divider count an apply's zero-width refusal toward its rebuild.
    ///
    /// The refusal is right (#868), but with H_ctrl off every display it returns
    /// before Phase 1 and the strand becomes permanent (#978). Withheld during a
    /// ⌘-drag, since replacing the window strands the drag.
    func recoverStrandedHiddenDividerBeforeRefusing(
        guardSource: String,
        controlItems: ControlItemPair,
        items: [MenuBarItem]
    ) {
        guard appState?.isDraggingMenuBarItem != true else { return }
        _ = recoverParkedHiddenDividerIfNeeded(
            trigger: .refusedApply(source: guardSource),
            hiddenControlItem: controlItems.hidden,
            // CGDisplayBounds shares the top-left origin space of the item
            // bounds; NSScreen.frame does not.
            screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) },
            managedItemCount: items.count { item in
                (item.canBeHidden || item.tag == .visibleControlItem)
                    && item.isMovable
                    && !item.isControlItem
            }
        )
    }

    /// Persists the profile's pinning sets and section order at a success exit.
    /// No-op for .savedOrder.
    ///
    /// An uncancelled exit doesn't mean the moves worked, so the section order
    /// is withheld on an unfinished batch, or the bar drifts every retry (#900, #978).
    /// Pinning is the profile's own declaration and is always written.
    private func persistProfileStateOnSuccess(source: ApplySource) {
        guard case .profile = source else { return }
        persistPinnedBundleIDs()
        guard !hasUnfinishedMoveBatch else {
            MenuBarItemManager.diagLog.warning(
                "Skipping the profile's saved section order write; the bulk apply left planned moves unenacted"
            )
            return
        }
        persistSavedSectionOrder()
        priorProfileApplySnapshot = nil
    }

    /// Stops late-arrival re-sorts from re-triggering on evaluated items.
    /// No-op for .savedOrder.
    private func updateProfileSortedSnapshot(source: ApplySource, items: [MenuBarItem]) {
        guard case .profile = source else { return }
        profileSortedItemIdentifiers = Set(
            items
                .filter { !$0.isControlItem }
                .map(\.uniqueIdentifier)
        )
    }

    /// Refreshes the sorted snapshot and clears the in-flight flag. No-op for .savedOrder.
    private func clearProfileState(source: ApplySource, items: [MenuBarItem]) {
        updateProfileSortedSnapshot(source: source, items: items)
        guard case .profile = source else { return }
        isApplyingProfileLayout = false
    }

    /// Phase 7's teardown for a no-moves apply. Without it (common on display
    /// reconnect) isApplyingProfileLayout leaks and blocks applySavedLayout for the session.
    func concludeProfileApplyWithoutMoves(source: ApplySource, items: [MenuBarItem]) {
        persistProfileStateOnSuccess(source: source)
        clearProfileState(source: source, items: items)
    }

    /// Schedules a full cache cycle, then image cache cleanup, on a separate Task.
    ///
    /// The outer cacheItemsRegardless holds cacheGate while awaiting this apply,
    /// so an inline recache would be dropped and leave quit apps in the cache.
    /// uiSettleDelay lets WindowServer settle first.
    private func scheduleDeferredCacheRefresh() {
        Task { [weak self] in
            try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
            guard let self else { return }
            // Re-entering applySavedLayout would live-lock on windowID churn.
            await self.cacheItemsRegardless(
                skipRecentMoveCheck: true,
                skipSavedLayoutApply: true
            )
            guard let appState = self.appState else { return }
            appState.imageCache.performCacheCleanup()
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        }
    }

    /// Moves items to match a profile's sections and order in a single pass.
    /// Matches per-item identifiers, since Control Center shares one bundle ID.
    func applyProfileLayout(
        _ spec: ProfileLayoutSpec,
        source: ApplySource = .profile,
        automatic: Bool = false,
        duringSettling: Bool = false,
        enforceConcealedSectionOrder: Bool = false,
        shouldBegin: (@MainActor () -> Bool)? = nil
    ) async {
        let pinnedHidden = spec.pinnedHidden
        let pinnedAlwaysHidden = spec.pinnedAlwaysHidden
        let rawSectionOrder = spec.sectionOrder
        let rawItemSectionMap = spec.itemSectionMap
        let rawItemOrder = spec.itemOrder
        // Older profiles name some items by their helper (e.g. the Little Snitch agent).
        // Migrate so the plan matches live identifiers; disk is rewritten on next save.
        let sectionOrder = LayoutSolver.canonicalizedSectionOrder(rawSectionOrder)
        let itemOrder = LayoutSolver.canonicalizedSectionOrder(rawItemOrder)
        let itemSectionMap = Dictionary(
            rawItemSectionMap.map { (LayoutSolver.canonicalIdentifier($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        // MARK: Phase 0: gate on startup settling

        // An apply during settling is shadowed and breaks late-arrival re-sorts.
        // The settling early apply is exempt: its caller holds cacheGate, so
        // waiting here deadlocks until the settling deadline (#943).
        if !duringSettling {
            await waitForStartupSettlingToEnd()
        }

        // Automatic applies wait for a lull. A profile the user just picked can't:
        // they're watching for it.
        if automatic {
            // Before the idle wait and armProfileState, so manual mode costs nothing.
            let automaticArrangementEnabled = (Defaults.object(forKey: .automaticArrangementEnabled) as? Bool)
                ?? Defaults.DefaultValue.automaticArrangementEnabled
            guard automaticArrangementEnabled else {
                MenuBarItemManager.diagLog.info(
                    "Profile layout: skipping automatic apply; automaticArrangementEnabled is false (manual arrangement only)"
                )
                return
            }
            // Also checked here, since every automatic caller funnels through.
            guard isAutomaticBulkApplyPermitted(caller: "Profile layout") else {
                return
            }
            guard await waitForBulkApplyIdleWindow() else {
                MenuBarItemManager.diagLog.info(
                    "Profile layout: deferring automatic apply because user input stayed active"
                )
                return
            }
        }

        // A newer apply may have cancelled us during the settling wait.
        if Task.isCancelled {
            return
        }
        guard shouldBegin?() ?? true else {
            MenuBarItemManager.diagLog.info(
                "applyProfileLayout: skipping automatic apply superseded during its idle wait"
            )
            return
        }

        // MARK: Phase 1: persist state and arm in-flight flags

        armProfileState(
            source: source,
            pinnedHidden: pinnedHidden,
            pinnedAlwaysHidden: pinnedAlwaysHidden,
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder
        )

        // Captured before any await lets a newer apply re-arm.
        let applyToken = profileApplyToken

        // Keeps saveSectionOrder from capturing intermediate positions.
        isRestoringItemOrder = true
        isRestoringItemOrderTimestamp = Date()
        defer {
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        guard !itemOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applyProfileLayout: no item order, skipping")
            concludeProfileApplyWithoutMoves(source: source, items: [])
            return
        }
        guard let appState else {
            MenuBarItemManager.diagLog.error("applyProfileLayout: missing appState")
            clearProfileState(source: source, items: [])
            return
        }

        // MARK: Phase 2: discover items, classify sections, build sequences

        let hiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .hidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
        let alwaysHiddenWID: CGWindowID? = appState.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window
            .flatMap { CGWindowID(exactly: $0.windowNumber) }

        // Target order, right to left. Control item UIDs are added once the
        // ControlItemPair is known.
        var desiredFlat = [String]()
        for key in ["visible", "hidden", "alwaysHidden"] {
            if let order = itemOrder[key] {
                desiredFlat.append(contentsOf: order)
            }
        }

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        // A clone would be planned as an unmanaged item and reshuffle the bar.
        items.removeAll(where: \.isSystemClone)
        guard shouldBegin?() ?? true else {
            MenuBarItemManager.diagLog.info(
                "applyProfileLayout: abandoning automatic apply superseded during item discovery"
            )
            clearProfileState(source: source, items: items)
            scheduleDeferredCacheRefresh()
            return
        }

        // uniqueIdentifier derives from sourcePID, so with most unresolved matching is unreliable.
        let unresolvedSourcePIDCount = items.count { $0.sourcePID == nil }
        if Self.majorityOfSourcePIDsUnresolved(unresolvedCount: unresolvedSourcePIDCount, itemCount: items.count) {
            MenuBarItemManager.diagLog.info(
                "applyProfileLayout: skipping, \(unresolvedSourcePIDCount)/\(items.count) items have unresolved sourcePIDs (XPC resolution likely failed)"
            )
            clearProfileState(source: source, items: items)
            return
        }

        // A synthetic Cmd-drag would tear down an open menu (Wi-Fi picker, input methods).
        let menuIsOpen = await isAnyMenuBarItemMenuOpen()
        guard shouldBegin?() ?? true else {
            MenuBarItemManager.diagLog.info(
                "applyProfileLayout: abandoning automatic apply superseded during its menu check"
            )
            clearProfileState(source: source, items: items)
            scheduleDeferredCacheRefresh()
            return
        }
        if menuIsOpen {
            MenuBarItemManager.diagLog.info("applyProfileLayout: skipping, a menu bar item menu is open")
            clearProfileState(source: source, items: items)
            return
        }

        guard var itemsCopy = Optional(items),
              let controlItems = ControlItemPair(
                  items: &itemsCopy,
                  hiddenControlItemWindowID: hiddenWID,
                  alwaysHiddenControlItemWindowID: alwaysHiddenWID
              )
        else {
            MenuBarItemManager.diagLog.error("applyProfileLayout: missing control items")
            clearProfileState(source: source, items: items)
            return
        }

        // Without the always-hidden divider every always-hidden item reads as hidden,
        // and the no-op moves repeat every pass (#881). Same rule as saveSectionOrder (#849).
        guard LayoutSolver.isAlwaysHiddenSectionResolved(
            hasAlwaysHiddenControlItem: controlItems.alwaysHidden != nil,
            isAlwaysHiddenSectionEnabled: appState.menuBarManager
                .section(withName: .alwaysHidden)?.isEnabled ?? false
        ) else {
            MenuBarItemManager.diagLog.warning(
                "applyProfileLayout: skipping, always-hidden divider unresolved while its section is enabled"
            )
            clearProfileState(source: source, items: items)
            return
        }

        // AX-frame correlation is fine for reading, not for any drag: every
        // destination depends on section classification.
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.warning(
                "applyProfileLayout: skipping, control items resolved only by provisional AX-frame correlation"
            )
            if case .profile = source {
                restoreProfileStateAfterAbortedApply(token: applyToken)
            }
            return
        }

        // Grouped by section: raw X order interleaves sections and breaks LCS.
        var context = CacheContext(
            controlItems: controlItems,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )

        func isProfileItem(_ item: MenuBarItem) -> Bool {
            (item.canBeHidden || item.tag == .visibleControlItem) && item.isMovable
        }

        let hiddenCtrlUID = controlItems.hidden.uniqueIdentifier
        let ahCtrlUID = controlItems.alwaysHidden?.uniqueIdentifier

        // Classify once: findSection re-reads WindowServer, and a show()-driven
        // control-item move can flip results between here and Phase 1.
        // Keyed by windowID because items on several displays share an identifier.
        var sectionByWindowID: [CGWindowID: MenuBarSection.Name] = [:]
        for item in items where isProfileItem(item) {
            if let section = context.findSection(for: item) {
                sectionByWindowID[item.windowID] = section
            }
        }

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

        // The dividers are appended explicitly below; listing them here too
        // doubles them and makes LCS plan spurious divider moves.
        var sectionUIDs = [MenuBarSection.Name: [String]]()
        for sectionName in [MenuBarSection.Name.visible, .hidden, .alwaysHidden] {
            let sectionItems = items.filter { item in
                guard isProfileItem(item) else { return false }
                let uid = item.uniqueIdentifier
                guard uid != hiddenCtrlUID, uid != ahCtrlUID else { return false }
                return sectionByWindowID[item.windowID] == sectionName
            }
            // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
            // Changing this string breaks log-replay regression tests.
            MenuBarItemManager.diagLog.debug(
                "applyProfileLayout: current \(sectionName.logString) has \(sectionItems.count) items: \(sectionItems.map(\.uniqueIdentifier))"
            )
            sectionUIDs[sectionName] = sectionItems.map(\.uniqueIdentifier)
        }
        // Shared with the log-replay harness so both build currentFlat identically.
        var currentFlat = LayoutSolver.flattenCurrentSections(
            visible: sectionUIDs[.visible] ?? [],
            hidden: sectionUIDs[.hidden] ?? [],
            alwaysHidden: sectionUIDs[.alwaysHidden] ?? [],
            hiddenCtrlUID: hiddenCtrlUID,
            ahCtrlUID: ahCtrlUID
        )

        let currentSet = Set(currentFlat)
        var desiredFiltered = desiredFlat.filter { currentSet.contains($0) }

        // Past every early return, so only an apply that saw the bar counts as
        // evidence. Control items are excluded; they'd dilute the ledger's ratio.
        let plannedIdentifiers = Set(itemOrder.values.joined())
        staleIdentifierLedger.recordApply(
            planned: plannedIdentifiers,
            matched: plannedIdentifiers.intersection(currentSet)
        )

        // MARK: Phase 3: place unmanaged items via planUnmanagedPlacement

        // Items not in the profile go back to their saved spot, or follow
        // NewItemsPlacement if never seen.
        let visibleCtrlUID = items.first(where: { $0.tag == .visibleControlItem })?.uniqueIdentifier
        let desiredSet = Set(desiredFiltered)
        // Unresolved Item-N widgets never match a profile entry and would be
        // relocated every cycle. Exclude them until they resolve.
        let provisionalIdentityUIDs = LayoutSolver.provisionalIdentityUIDs(items: items)
        // Otherwise a trigger-owned item is treated as unmanaged and moved back
        // out of where the trigger put it.
        let triggerControlledUIDs = triggerProtectedUIDs(among: currentFlat, items: items)
        let unmanagedUIDs = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: currentFlat,
            desiredUIDs: desiredSet,
            hiddenCtrlUID: hiddenCtrlUID,
            ahCtrlUID: ahCtrlUID,
            visibleCtrlUID: visibleCtrlUID,
            provisionalIdentityUIDs: provisionalIdentityUIDs,
            triggerControlledUIDs: triggerControlledUIDs
        )
        if !unmanagedUIDs.isEmpty {
            // Pinning stays empty: this only places unmanaged items.
            // Prune before the lookup: saved positions are indices, so a ghost
            // entry shifts returning items. The same pruned order feeds the apply below.
            let prunedSavedOrder = staleIdentifierLedger.pruning(savedSectionOrder)
            let desiredForUnmanaged = DesiredLayout.fromSavedSectionOrder(
                prunedSavedOrder,
                newItemsPlacement: newItemsPlacement
            )
            let placements = LayoutReconciler.unmanagedPlacementPlan(
                desired: desiredForUnmanaged,
                unmanagedUIDs: unmanagedUIDs,
                currentUIDs: Set(currentFlat)
            )

            // The most direct signal for "why did X move?" reports.
            for uid in unmanagedUIDs {
                let placementSummary = switch placements[uid] {
                case let .saved(section, index)?:
                    "saved(section=\(section.logString), index=\(index))"
                case let .newItemAnchored(section, anchorUID, relation)?:
                    "newItemAnchored(section=\(section.logString), anchor=\(anchorUID), relation=\(String(describing: relation)))"
                case let .newItemDefault(section)?:
                    "newItemDefault(section=\(section.logString))"
                case nil:
                    "<no placement returned>"
                }
                // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
                // Changing this string breaks log-replay regression tests.
                MenuBarItemManager.diagLog.debug(
                    "Profile layout: planUnmanagedPlacement \(uid) -> \(placementSummary)"
                )
            }

            let applied = LayoutReconciler.applyUnmanagedPlacementsToDesired(
                placements: placements,
                unmanagedUIDs: unmanagedUIDs,
                desiredFiltered: desiredFiltered,
                sectionMap: sectionMap,
                savedSectionOrder: prunedSavedOrder,
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

        // On notched displays, eject what doesn't fit into hidden; the Thaw icon
        // stays last in visible. No NSScreen.main fallback: guessing the wrong
        // display is the failure this gate prevents, so it fails closed.
        let activeMenuBarScreen = NSScreen.screenWithActiveMenuBar
        let activeIsMainDisplay = activeMenuBarScreen?.displayID == CGMainDisplayID()
        // A non-main notched display hosts items only while focused; ejecting
        // there strands them in hidden.
        if appState.settings.advanced.enableMenuBarItemOverflow {
            if let screen = activeMenuBarScreen, screen.hasNotch, !activeIsMainDisplay {
                MenuBarItemManager.diagLog.debug(
                    "Notch overflow: skipping — active notched display \(screen.displayID) is a secondary "
                        + "(main display is \(CGMainDisplayID())); overflow only manages the main menu bar, "
                        + "so the saved layout is honoured verbatim"
                )
            } else if activeMenuBarScreen == nil {
                MenuBarItemManager.diagLog.debug(
                    "Notch overflow: skipping — active menu bar display is unknown; "
                        + "overflow does not guess a screen, so the saved layout is honoured verbatim"
                )
            }
        }
        if LayoutSolver.shouldManageNotchOverflow(
            overflowEnabled: appState.settings.advanced.enableMenuBarItemOverflow,
            activeScreenKnown: activeMenuBarScreen != nil,
            activeHasNotch: activeMenuBarScreen?.hasNotch ?? false,
            activeIsMainDisplay: activeIsMainDisplay
        ),
            let screen = activeMenuBarScreen,
            let notch = screen.frameOfNotch
        {
            let budget = Self.computeNotchOverflowBudget(
                items: items,
                screen: screen,
                notch: notch,
                spacingOffset: appState.spacingManager.offset
            )
            let rightBoundary = budget.rightBoundary
            var availableWidth = budget.availableWidth

            let visibleUIDs = Array(desiredFiltered.prefix(while: { $0 != hiddenCtrlUID }))
            var uidWidths = [String: CGFloat]()
            for uid in visibleUIDs {
                if let item = items.first(where: { $0.uniqueIdentifier == uid && isProfileItem($0) }) {
                    uidWidths[uid] = item.bounds.width
                }
            }

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

            // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
            // Changing this string breaks log-replay regression tests.
            MenuBarItemManager.diagLog.debug(
                """
                Notch overflow budget: \(budget.logString) \
                visibleUIDs.count=\(visibleUIDs.count) chevronFootprint=\(chevronFootprint)
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

            // Replace, not union, so items that fit again drop out.
            notchOverflowEjectedUIDs = Set(overflowResult.overflowUIDs)

            if !overflowResult.overflowUIDs.isEmpty {
                // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
                // Changing this string breaks log-replay regression tests.
                MenuBarItemManager.diagLog.info(
                    "Profile layout: notch overflow; \(overflowResult.overflowUIDs.count) item(s) moved from visible to hidden"
                )
                desiredFiltered = overflowResult.updatedDesiredFiltered
                sectionMap = overflowResult.updatedSectionMap
            }
        } else if !notchOverflowEjectedUIDs.isEmpty {
            // No overflow here, so the ejection bookkeeping is obsolete.
            notchOverflowEjectedUIDs.removeAll()
        }

        // Re-check against Phase 2's fresh bounds: the dividers can collapse after
        // the cache snapshot, misreading hidden as visible and persisting the damage (#868).
        //
        // Profile applies are exempt: filling an empty hidden section legitimately
        // starts from adjacent dividers.
        if case .savedOrder = source,
           !LayoutSolver.hiddenSectionHasRoom(
               hiddenControlItemMinX: controlItems.hidden.bounds.minX,
               alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX,
               savedHiddenItemCount: itemOrder[sectionKey(for: .hidden)]?.count ?? 0,
               liveHiddenItemCount: LayoutSolver.liveHiddenItemCount(
                   itemBounds: items.map(\.bounds),
                   hiddenControlItemMinX: controlItems.hidden.bounds.minX,
                   alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX
               ),
               hasVisibleItemParkedOffBar: LayoutSolver.hasVisibleItemParkedOffBar(
                   itemBounds: items.map(\.bounds),
                   hiddenControlItemMinX: controlItems.hidden.bounds.minX,
                   screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
               )
           )
        {
            MenuBarItemManager.diagLog.warning(
                "applyProfileLayout: skipping (savedOrder); hidden section has zero width between the dividers (hidden.minX=\(controlItems.hidden.bounds.minX) windowID=\(controlItems.hidden.windowID), alwaysHidden.maxX=\(controlItems.alwaysHidden?.bounds.maxX.description ?? "nil") windowID=\(controlItems.alwaysHidden?.windowID.description ?? "nil"))"
            )
            recoverStrandedHiddenDividerBeforeRefusing(
                guardSource: "applyProfileLayout",
                controlItems: controlItems,
                items: items
            )
            clearProfileState(source: source, items: items)
            return
        }

        guard shouldBegin?() ?? true else {
            MenuBarItemManager.diagLog.info(
                "applyProfileLayout: abandoning automatic apply superseded while planning"
            )
            clearProfileState(source: source, items: items)
            scheduleDeferredCacheRefresh()
            return
        }

        // A user move that wins moveGate between items invalidates the next move.
        var batchMovePreflight = BatchMovePreflightState()
        var batchYieldedForInput = false
        let inputPause = Duration.milliseconds(max(
            0,
            (Defaults.object(forKey: .inputPauseThresholdMs) as? Int)
                ?? Defaults.DefaultValue.inputPauseThresholdMs
        ))
        func shouldBeginBatchMove() -> Bool {
            guard batchMovePreflight.shouldBeginMove(
                currentTimestamp: lastMoveOperationTimestamp,
                initialPreflight: {
                    shouldBegin?() ?? true
                }
            ) else {
                return false
            }
            let inputPaused = hasUserPausedPhysicalInput(for: inputPause)
            if Self.automaticBatchShouldYieldForInput(
                automatic: automatic,
                userHasPausedPhysicalInput: inputPaused
            ) {
                batchYieldedForInput = true
                return false
            }
            return true
        }
        func didFinishBatchMove() {
            batchMovePreflight.recordMoveGateExit(
                timestamp: lastMoveOperationTimestamp
            )
        }

        // Divider-order gate (#1027): dividers drifted into foreign sections pass the
        // room gate but garble every classification. Profile applies are gated too.
        let dividerBounds = dividerControlItemBounds(items: items, controlItems: controlItems)
        if !LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: dividerBounds.visible,
            hiddenControlItemBounds: dividerBounds.hidden,
            alwaysHiddenControlItemBounds: dividerBounds.alwaysHidden
        ) {
            MenuBarItemManager.diagLog.warning(
                "applyProfileLayout: skipping (\(source)); section dividers are out of order (visibleCtrl.minX=\(dividerBounds.visible?.minX.description ?? "unresolved"), hidden.minX=\(dividerBounds.hidden.minX), alwaysHiddenCtrl.minX=\(dividerBounds.alwaysHidden?.minX.description ?? "unresolved"))"
            )
            recoverStrandedHiddenDividerBeforeRefusing(
                guardSource: "applyProfileLayout",
                controlItems: controlItems,
                items: items
            )
            await recoverMisplacedVisibleControlItem(
                controlItems: controlItems,
                items: items
            )
            clearProfileState(source: source, items: items)
            return
        }

        // Hide the cursor for the whole apply. Captured in CG space because
        // CGWarpMouseCursorPosition takes it; AppKit coordinates warped to the
        // wrong display on stacked setups.
        //
        // restoreCursor() runs after the last move, not at exit; the defer
        // covers early returns.
        let savedCursorPosition = MouseHelpers.locationCoreGraphics
        let cursorOwnershipStartedAt = ContinuousClock.now
        var cursorRestored = false
        func restoreCursor() {
            guard !cursorRestored else { return }
            cursorRestored = true
            let physicalInputOccurred = MouseHelpers.physicalPointerInputOccurred(
                since: cursorOwnershipStartedAt
            )
            // Don't reclaim the pointer if the user moved or scrolled during the batch.
            if let savedCursorPosition,
               MouseHelpers.shouldRestoreSavedCursorPosition(
                   physicalPointerInputOccurred: physicalInputOccurred
               )
            {
                MouseHelpers.restoreCursorPosition(to: savedCursorPosition)
            } else if physicalInputOccurred {
                MenuBarItemManager.diagLog.debug(
                    "Profile layout: preserving physical pointer movement made during the batch"
                )
            }
            MouseHelpers.showCursor()
        }
        MouseHelpers.hideCursor(watchdogTimeout: .seconds(30))
        defer { restoreCursor() }

        // Lets postMoveEvents skip its per-item cursor hide/show.
        isBulkApplyInProgress = true
        defer { isBulkApplyInProgress = false }

        // MARK: Phase 6: LCS execution

        // ── Sub-phase 0: Move control items to optimal boundary positions ──
        //
        // One control-item move re-sections everything it crosses, which can
        // beat moving items individually.
        var movedCount = 0
        var didAttemptHCtrl = false
        // Either way of repairing the boundary leaves AH_ctrl's section inputs stale.
        var didCrossHiddenBoundary = false
        var canRepositionControlItems = controlItems.canRepositionControlItems
        // Planned but unenacted moves; saveSectionOrder must not save the result (#900).
        var unenactedMoveCount = 0

        /// Automatic applies only; user-invoked ones have their own UI.
        func enqueueApplyMoveFailure(
            _ error: any Error,
            item: MenuBarItem,
            destination: MoveDestination?,
            expectedSection: MenuBarSection.Name?
        ) {
            guard automatic else { return }
            let failureSource = switch source {
            case .profile: "the active profile"
            case .savedOrder: "the saved layout"
            }
            enqueueAutomaticMoveFailureReport(
                of: item,
                to: destination,
                expectedSection: expectedSection,
                error: error,
                source: failureSource
            )
        }

        /// Counts one more unenacted move, feeds the circuit breaker, and tears
        /// down profile state before the deferred refresh. Pass nil if you log yourself.
        func abandonApply(reason: String?, items: [MenuBarItem]) {
            unenactedMoveCount += 1
            if let reason {
                MenuBarItemManager.diagLog.warning(
                    "applyProfileLayout: \(reason); abandoning the remaining apply"
                )
            }
            recordBulkApplyOutcome(unenactedMoveCount: unenactedMoveCount)
            clearProfileState(source: source, items: items)
            scheduleDeferredCacheRefresh()
        }

        /// A manual move superseding the plan isn't a failure: no backoff, no breaker trip.
        func finishSupersededApply(items: [MenuBarItem]) {
            if batchYieldedForInput {
                MenuBarItemManager.diagLog.info(
                    "applyProfileLayout: physical input resumed between moves; deferring the automatic remainder"
                )
                if case .profile = source {
                    restoreProfileStateAfterAbortedApply(token: applyToken)
                }
                scheduleDeferredCacheRefresh()
                return
            }
            MenuBarItemManager.diagLog.info(
                "applyProfileLayout: user move superseded the automatic plan; leaving the user's arrangement authoritative"
            )
            clearProfileState(source: source, items: items)
            scheduleDeferredCacheRefresh()
        }

        // From the snapshot, not findSection, which may have changed since.
        var currentVisibleSet = Set<String>()
        var currentHiddenSet = Set<String>()
        var currentAHSet = Set<String>()
        for item in items where isProfileItem(item) {
            switch sectionByWindowID[item.windowID] {
            case .visible:
                currentVisibleSet.insert(item.uniqueIdentifier)
            case .hidden:
                currentHiddenSet.insert(item.uniqueIdentifier)
            case .alwaysHidden:
                currentAHSet.insert(item.uniqueIdentifier)
            case nil:
                break
            }
        }

        let desiredHiddenSet = Set(itemOrder["hidden"] ?? [])
        let desiredAHSet = Set(itemOrder["alwaysHidden"] ?? [])
        // Logged for the log-replay harness and used by the hidden-divider check below.
        let desiredVisibleSet = Set(itemOrder["visible"] ?? [])

        let wrongInHidden = currentHiddenSet.subtracting(desiredHiddenSet).intersection(desiredAHSet)
        let wrongInAH = currentAHSet.subtracting(desiredAHSet).intersection(desiredHiddenSet)
        var crossSectionMoves = wrongInHidden.count + wrongInAH.count

        // Broader than crossSectionMoves: drift with no counterpart in the other
        // desired section is still fixed by one AH_ctrl move.
        let needsHiddenMove = currentAHSet.intersection(desiredHiddenSet)
        let needsAHMove = currentHiddenSet.intersection(desiredAHSet)
        var totalSectionMismatch = needsHiddenMove.count + needsAHMove.count

        // Items on the wrong side of H_ctrl. With H_ctrl drifted past every item,
        // both tallies above and the LCS see nothing wrong (#879). One H_ctrl move fixes it...
        let hiddenBoundaryOffenders = LayoutSolver.hiddenBoundaryOffenders(
            currentVisible: currentVisibleSet,
            currentHidden: currentHiddenSet,
            currentAlwaysHidden: currentAHSet,
            desiredVisible: desiredVisibleSet,
            desiredHidden: desiredHiddenSet,
            desiredAlwaysHidden: desiredAHSet,
            overflowExemptUIDs: notchOverflowEjectedUIDs
        )
        let hiddenBoundaryMismatch = hiddenBoundaryOffenders.count
        // Offenders absorbed by the notch exemption, so a soak can tell by-design
        // divergence apart. Phase 4 already refreshed the set.
        let exemptedEjectedCount = notchOverflowEjectedUIDs.intersection(currentHiddenSet)
            .intersection(desiredVisibleSet).count

        // ...but only when the divider drifted. Drop our own items first, or the
        // chevron makes a collapsed bar never qualify.
        let liveControlUIDs = Set(items.lazy.filter(\.isControlItem).map(\.uniqueIdentifier))
        let liveConcealedCount = currentHiddenSet
            .union(currentAHSet)
            .subtracting(liveControlUIDs)
            .count
        let liveVisibleCount = currentVisibleSet
            .subtracting(liveControlUIDs)
            .count
        let shouldMoveHiddenDivider = LayoutSolver.shouldMoveHiddenDivider(
            liveConcealedCount: liveConcealedCount,
            liveVisibleCount: liveVisibleCount
        )

        // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
        // Changing this string breaks log-replay regression tests.
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: ahCtrlUID=\(ahCtrlUID ?? "nil"), crossSectionMoves=\(crossSectionMoves), totalSectionMismatch=\(totalSectionMismatch)"
        )
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: currentHidden=\(currentHiddenSet.sorted())"
        )
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: currentAH=\(currentAHSet.sorted())"
        )
        // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
        // Changing this string breaks log-replay regression tests.
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: desiredHidden=\(desiredHiddenSet.sorted())"
        )
        // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
        // Changing this string breaks log-replay regression tests.
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: desiredAH=\(desiredAHSet.sorted())"
        )
        // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
        // Changing this string breaks log-replay regression tests.
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: desiredVisible=\(desiredVisibleSet.sorted())"
        )
        // Format contract: parsed by ProfileLayoutLogReplayTests.parse(_:).
        // Changing this string breaks log-replay regression tests.
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: hiddenBoundaryMismatch=\(hiddenBoundaryMismatch)"
        )
        if exemptedEjectedCount > 0 {
            MenuBarItemManager.diagLog.debug(
                "Profile layout Phase 1: \(exemptedEjectedCount) notch-overflow-ejected item(s) exempt from the H_ctrl boundary check (by-design divergence)"
            )
        }
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: liveConcealed=\(liveConcealedCount), liveVisible=\(liveVisibleCount), moveHiddenDivider=\(shouldMoveHiddenDivider)"
        )
        // A zero mismatch alone must not clear the streak; a divider can strand
        // with a consistent boundary (#978). Use the recovery's both-edges test.
        if hiddenBoundaryMismatch == 0,
           !LayoutSolver.isFullyOffScreen(
               bounds: controlItems.hidden.bounds,
               screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
           )
        {
            resetParkedHiddenDividerRecovery()
        }

        // ── Sub-phase 1: Restore the visible/hidden boundary ──
        //
        // Before AH_ctrl placement so it sees a correct pair. shouldMoveHiddenDivider
        // picks a divider drag or per-item moves.
        if hiddenBoundaryMismatch > 0, canRepositionControlItems, !Task.isCancelled {
            MenuBarItemManager.diagLog.debug(
                "Profile layout: \(hiddenBoundaryMismatch) item(s) on the wrong side of H_ctrl, moving \(shouldMoveHiddenDivider ? "H_ctrl to the boundary" : "them to H_ctrl")"
            )

            let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard shouldBeginBatchMove() else {
                finishSupersededApply(items: allFreshItems)
                return
            }
            var allFreshItemsCopy = allFreshItems
            guard let freshControl = ControlItemPair(
                items: &allFreshItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems else {
                abandonApply(
                    reason: "control items degraded before moving H_ctrl",
                    items: allFreshItems
                )
                return
            }
            // CG space, like item bounds; NSScreen frames are flipped.
            let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
            // Every apply source feeds the recovery (#978). Not during a ⌘-drag:
            // replacing the window strands the drag.
            if !appState.isDraggingMenuBarItem,
               recoverParkedHiddenDividerIfNeeded(
                   trigger: .boundaryMismatch(hiddenBoundaryMismatch),
                   hiddenControlItem: freshControl.hidden,
                   screenFrames: screenFrames,
                   // Phase 1 sets fold items that share an identifier across displays.
                   managedItemCount: allFreshItems.count(where: {
                       isProfileItem($0) && !$0.isControlItem
                   })
               )
            {
                // Not a failed apply, so the one retry can verify the fresh divider.
                clearProfileState(source: source, items: allFreshItems)
                scheduleDeferredCacheRefresh()
                return
            }
            if shouldMoveHiddenDivider {
                // A parked anchor fails every retry: AppKit snaps the divider back
                // on mouse-up (#881). The LCS pass handles parked items.
                let liveMovableUIDs = Set(
                    allFreshItems.lazy.filter { item in
                        guard item.isMovable, isProfileItem(item) else { return false }
                        return LayoutSolver.isOnScreen(bounds: item.bounds, screenFrames: screenFrames)
                    }.map(\.uniqueIdentifier)
                )
                // Our control items always pass the filters above, and anchoring on
                // the chevron collapses the section being restored (#958).
                let controlItemUIDs = Set(
                    allFreshItems.lazy.filter(\.isControlItem).map(\.uniqueIdentifier)
                )
                let desiredHidden = itemOrder["hidden"] ?? []
                let desiredVisible = itemOrder["visible"] ?? []
                let anchor = LayoutSolver.planHiddenDividerAnchor(
                    desiredHidden: desiredHidden,
                    desiredVisible: desiredVisible,
                    liveMovableUIDs: liveMovableUIDs,
                    unanchorableUIDs: controlItemUIDs
                )

                if let anchor {
                    let hItem = freshControl.hidden
                    let anchorUID = switch anchor {
                    case let .rightOf(uid), let .leftOf(uid): uid
                    }
                    if let anchorItem = allFreshItems.first(where: { $0.uniqueIdentifier == anchorUID }) {
                        let dest: MoveDestination = switch anchor {
                        case .rightOf: .rightOfItem(anchorItem)
                        case .leftOf: .leftOfItem(anchorItem)
                        }
                        if !LayoutSolver.isOnScreen(bounds: hItem.bounds, screenFrames: screenFrames) {
                            // A parked H_ctrl snaps back to its autosave position on
                            // mouse-up every attempt (#899). The LCS pass works without it.
                            unenactedMoveCount += 1
                            MenuBarItemManager.diagLog.warning(
                                "Profile layout: H_ctrl is parked offscreen (minX=\(hItem.bounds.minX)), skipping the boundary move"
                            )
                        } else if failureLedger.isUnderBackoff(for: hItem) {
                            // Otherwise every re-sort retries a move that can't land (#899).
                            unenactedMoveCount += 1
                            MenuBarItemManager.diagLog.warning(
                                "Profile layout: H_ctrl under move-failure backoff, skipping"
                            )
                        } else {
                            MenuBarItemManager.diagLog.debug("Profile layout: moving H_ctrl → \(dest.logString)")
                            didAttemptHCtrl = true
                            do {
                                try await move(
                                    item: hItem,
                                    to: dest,
                                    skipInputPause: true,
                                    options: .init(
                                        shouldBegin: shouldBeginBatchMove,
                                        didFinishWhileHoldingGate: didFinishBatchMove
                                    )
                                )
                                movedCount += 1
                                failureLedger.recordSuccess(for: hItem)
                                try? await Task.sleep(for: .milliseconds(200))
                            } catch {
                                if case EventError.moveSuperseded = error {
                                    finishSupersededApply(items: allFreshItems)
                                    return
                                }
                                unenactedMoveCount += 1
                                // A cancellation says nothing about the divider.
                                if Task.isCancelled {
                                    MenuBarItemManager.diagLog.debug(
                                        "Profile layout: H_ctrl move interrupted by a newer apply; leaving it unrecorded"
                                    )
                                } else {
                                    if !Self.moveAlreadyFiledFailure(for: error) {
                                        failureLedger.recordFailure(for: hItem, kind: Self.failureKind(of: error))
                                    }
                                    MenuBarItemManager.diagLog.error("Profile layout: failed to move H_ctrl: \(error)")
                                    enqueueApplyMoveFailure(
                                        error,
                                        item: hItem,
                                        destination: dest,
                                        expectedSection: nil
                                    )
                                }
                            }
                        }
                    }
                } else if let refusedAnchor = LayoutSolver.hiddenDividerAnchorCandidate(
                    desiredHidden: desiredHidden,
                    desiredVisible: desiredVisible,
                    liveMovableUIDs: liveMovableUIDs
                ).flatMap({ controlItemUIDs.contains($0) ? $0 : nil }) {
                    // Kept apart from the case below: items are on the bar, just
                    // on the wrong side, which the LCS pass fixes.
                    MenuBarItemManager.diagLog.warning(
                        "Profile layout: only \(refusedAnchor) was left to anchor the H_ctrl boundary move; leaving the divider where it is"
                    )
                } else {
                    // Nothing to anchor against; the LCS pass still runs.
                    MenuBarItemManager.diagLog.warning(
                        "Profile layout: no anchor available for the H_ctrl boundary move"
                    )
                }
            } else if !LayoutSolver.isOnScreen(
                bounds: freshControl.hidden.bounds,
                screenFrames: screenFrames
            ) {
                // An off-display destination gets a press no owner sees (#899).
                // The recovery rebuilds it; until then the LCS pass makes progress.
                unenactedMoveCount += 1
                MenuBarItemManager.diagLog.warning(
                    "Profile layout: H_ctrl is parked offscreen (minX=\(freshControl.hidden.bounds.minX)), skipping the per-item boundary moves"
                )
            } else {
                // Move the strays to the divider, not the divider to them, which
                // would re-section most of the bar (#958).
                let hItem = freshControl.hidden
                let offenderUIDs = hiddenBoundaryOffenders.wronglyVisible
                    .union(hiddenBoundaryOffenders.wronglyConcealed)
                var offenders: [String: MenuBarItem] = [:]
                for item in allFreshItems where offenderUIDs.contains(item.uniqueIdentifier) {
                    guard item.isMovable,
                          LayoutSolver.isOnScreen(bounds: item.bounds, screenFrames: screenFrames)
                    else {
                        continue
                    }
                    offenders[item.uniqueIdentifier] = item
                }
                if offenders.count < offenderUIDs.count {
                    // Parked or immovable; the LCS pass brings these back.
                    MenuBarItemManager.diagLog.debug(
                        "Profile layout: \(offenderUIDs.count - offenders.count) boundary offender(s) not live and movable, leaving them to the LCS pass"
                    )
                }

                // Each move lands beside H_ctrl and pushes the last one out, so
                // walking away from the divider keeps the order.
                let toConceal = hiddenBoundaryOffenders.wronglyVisible
                    .compactMap { offenders[$0] }
                    .sorted { $0.bounds.minX < $1.bounds.minX }
                let toReveal = hiddenBoundaryOffenders.wronglyConcealed
                    .compactMap { offenders[$0] }
                    .sorted { $0.bounds.minX > $1.bounds.minX }

                for (item, dest, expectedSection) in toConceal.map({
                    ($0, MoveDestination.leftOfItem(hItem), MenuBarSection.Name.hidden)
                }) + toReveal.map({
                    ($0, MoveDestination.rightOfItem(hItem), MenuBarSection.Name.visible)
                }) {
                    if Task.isCancelled {
                        break
                    }
                    guard !failureLedger.isUnderBackoff(for: item) else {
                        unenactedMoveCount += 1
                        MenuBarItemManager.diagLog.debug(
                            "Profile layout: \(item.logString) under move-failure backoff, skipping the boundary move"
                        )
                        continue
                    }
                    MenuBarItemManager.diagLog.debug(
                        "Profile layout: moving \(item.logString) → \(dest.logString) to fix the H_ctrl boundary"
                    )
                    do {
                        try await move(
                            item: item,
                            to: dest,
                            skipInputPause: true,
                            options: .init(
                                shouldBegin: shouldBeginBatchMove,
                                didFinishWhileHoldingGate: didFinishBatchMove
                            )
                        )
                        movedCount += 1
                        didCrossHiddenBoundary = true
                        failureLedger.recordSuccess(for: item)
                        // The next target is computed from geometry this move changes.
                        try? await Task.sleep(for: .milliseconds(200))
                    } catch {
                        if case EventError.moveSuperseded = error {
                            finishSupersededApply(items: allFreshItems)
                            return
                        }
                        unenactedMoveCount += 1
                        // A cancellation says nothing about the item; don't back it off.
                        if Task.isCancelled {
                            MenuBarItemManager.diagLog.debug(
                                "Profile layout: boundary move for \(item.logString) interrupted by a newer apply; leaving it unrecorded"
                            )
                        } else {
                            if !Self.moveAlreadyFiledFailure(for: error) {
                                failureLedger.recordFailure(for: item, kind: Self.failureKind(of: error))
                            }
                            MenuBarItemManager.diagLog.error(
                                "Profile layout: failed to move \(item.logString) across the H_ctrl boundary: \(error)"
                            )
                            enqueueApplyMoveFailure(
                                error,
                                item: item,
                                destination: dest,
                                expectedSection: expectedSection
                            )
                        }
                    }
                }
            }
        }

        // The repair made the snapshot stale; reclassify before planning AH_ctrl.
        if didAttemptHCtrl || didCrossHiddenBoundary {
            var postMoveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard shouldBeginBatchMove() else {
                finishSupersededApply(items: postMoveItems)
                return
            }
            postMoveItems.removeAll(where: \.isSystemClone)
            var postMoveItemsCopy = postMoveItems
            if let postMoveControl = ControlItemPair(
                items: &postMoveItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ) {
                canRepositionControlItems = postMoveControl.canRepositionControlItems
                guard canRepositionControlItems else {
                    abandonApply(
                        reason: "control items degraded to provisional AX-frame correlation after moving H_ctrl",
                        items: postMoveItems
                    )
                    return
                }
                var postMoveContext = CacheContext(
                    controlItems: postMoveControl,
                    displayID: Bridging.getActiveMenuBarDisplayID()
                )

                sectionByWindowID.removeAll(keepingCapacity: true)
                for item in postMoveItems where isProfileItem(item) {
                    if let section = postMoveContext.findSection(for: item) {
                        sectionByWindowID[item.windowID] = section
                    }
                }

                currentVisibleSet.removeAll(keepingCapacity: true)
                currentHiddenSet.removeAll(keepingCapacity: true)
                currentAHSet.removeAll(keepingCapacity: true)
                for item in postMoveItems where isProfileItem(item) {
                    switch sectionByWindowID[item.windowID] {
                    case .visible:
                        currentVisibleSet.insert(item.uniqueIdentifier)
                    case .hidden:
                        currentHiddenSet.insert(item.uniqueIdentifier)
                    case .alwaysHidden:
                        currentAHSet.insert(item.uniqueIdentifier)
                    case nil:
                        break
                    }
                }

                let postWrongInHidden = currentHiddenSet
                    .subtracting(desiredHiddenSet)
                    .intersection(desiredAHSet)
                let postWrongInAH = currentAHSet
                    .subtracting(desiredAHSet)
                    .intersection(desiredHiddenSet)
                crossSectionMoves = postWrongInHidden.count + postWrongInAH.count

                let postNeedsHiddenMove = currentAHSet.intersection(desiredHiddenSet)
                let postNeedsAHMove = currentHiddenSet.intersection(desiredAHSet)
                totalSectionMismatch = postNeedsHiddenMove.count + postNeedsAHMove.count

                MenuBarItemManager.diagLog.debug(
                    "Profile layout: post-H_ctrl classification crossSectionMoves=\(crossSectionMoves), totalSectionMismatch=\(totalSectionMismatch)"
                )
            } else {
                MenuBarItemManager.diagLog.warning(
                    "Profile layout: could not reclassify sections after moving H_ctrl"
                )
                clearProfileState(source: source, items: postMoveItems)
                scheduleDeferredCacheRefresh()
                return
            }
        }

        if crossSectionMoves > 0 || totalSectionMismatch > 0,
           canRepositionControlItems,
           ahCtrlUID != nil
        {
            MenuBarItemManager.diagLog.debug(
                "Profile layout: \(crossSectionMoves) items would change hidden↔alwaysHidden, moving AH_ctrl instead"
            )

            let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard shouldBeginBatchMove() else {
                finishSupersededApply(items: allFreshItems)
                return
            }
            var allFreshItemsCopy = allFreshItems
            guard let freshControl = ControlItemPair(
                items: &allFreshItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems
            else {
                abandonApply(
                    reason: "control items degraded before moving AH_ctrl",
                    items: allFreshItems
                )
                return
            }
            // Since #991 nil means WindowServer doesn't know the divider at all
            // (torn down or disabled mid-apply), and every move below anchors on it.
            guard let ahItem = freshControl.alwaysHidden else {
                abandonApply(
                    reason: "always-hidden divider unresolved before moving AH_ctrl",
                    items: allFreshItems
                )
                return
            }

            // Place AH_ctrl left of the rightmost desired hidden item, or next to
            // H_ctrl when either section is empty.
            // CGDisplayBounds shares the item bounds' top-left origin; NSScreen.frame doesn't.
            let ahScreenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
            let desiredHiddenUIDs = itemOrder["hidden"] ?? []
            var dest: MoveDestination? = if let firstHiddenUID = desiredHiddenUIDs.first,
                                            let firstHidden = allFreshItems.first(where: { $0.uniqueIdentifier == firstHiddenUID && $0.isMovable })
            {
                .leftOfItem(firstHidden)
            } else {
                .leftOfItem(freshControl.hidden)
            }

            // Anchoring beside a parked item drags AH_ctrl into the parked zone
            // and inverts the pair (#978). The per-item fallback moves more but strands nothing.
            if let anchorBounds = dest?.targetItem.liveBounds,
               !LayoutSolver.isOnScreen(bounds: anchorBounds, screenFrames: ahScreenFrames)
            {
                MenuBarItemManager.diagLog.warning(
                    "Profile layout: skipping the AH_ctrl placement, its anchor is parked offscreen (minX=\(anchorBounds.minX)); moving AH_ctrl beside it would strand both"
                )
                dest = nil
            }

            if let dest, !Task.isCancelled {
                MenuBarItemManager.diagLog.debug("Profile layout: moving AH_ctrl → \(dest.logString)")
                do {
                    try await move(
                        item: ahItem,
                        to: dest,
                        skipInputPause: true,
                        options: .init(
                            shouldBegin: shouldBeginBatchMove,
                            didFinishWhileHoldingGate: didFinishBatchMove
                        )
                    )
                    movedCount += 1
                    try? await Task.sleep(for: .milliseconds(200))
                } catch {
                    if case EventError.moveSuperseded = error {
                        finishSupersededApply(items: allFreshItems)
                        return
                    }
                    unenactedMoveCount += 1
                    MenuBarItemManager.diagLog.error("Profile layout: failed to move AH_ctrl: \(error)")
                    enqueueApplyMoveFailure(
                        error,
                        item: ahItem,
                        destination: dest,
                        expectedSection: nil
                    )
                }
            }

            // Per-item fallback: when the two groups are interleaved (e.g. after a
            // fresh start) no single AH_ctrl position splits them, and the no-op
            // guard can skip the AH_ctrl move. Issue order is final order, since
            // the LCS pass re-sorts concealed sections only when enforced.
            let freshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard shouldBeginBatchMove() else {
                finishSupersededApply(items: freshItems)
                return
            }
            var freshItemsCopy = freshItems
            if let freshControl = ControlItemPair(
                items: &freshItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ) {
                guard freshControl.canRepositionControlItems else {
                    abandonApply(
                        reason: "control items degraded to provisional AX-frame correlation after moving AH_ctrl",
                        items: freshItems
                    )
                    return
                }
                guard let ahItem = freshControl.alwaysHidden else {
                    abandonApply(reason: nil, items: freshItems)
                    return
                }
                var verifyContext = CacheContext(
                    controlItems: freshControl,
                    displayID: Bridging.getActiveMenuBarDisplayID()
                )
                // By windowID so multi-display duplicates keep their own section.
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

                    // Each move lands just left of AH_ctrl and pushes the rest left,
                    // so index 0 moves first. See crossSectionFallbackMoveOrder.
                    let ahProfileOrder = itemOrder["alwaysHidden"] ?? []
                    let orderedCrossToAH = LayoutSolver.crossSectionFallbackMoveOrder(
                        profileOrder: ahProfileOrder,
                        crossing: crossToAH,
                        landingSlot: .rightmostOfAlwaysHidden
                    )
                    for uid in orderedCrossToAH {
                        guard !Task.isCancelled else { break }
                        guard
                            let item = freshItems.first(where: { $0.uniqueIdentifier == uid && isProfileItem($0) })
                        else { continue }
                        do {
                            try await move(
                                item: item,
                                to: .leftOfItem(ahItem),
                                skipInputPause: true,
                                options: .init(
                                    shouldBegin: shouldBeginBatchMove,
                                    didFinishWhileHoldingGate: didFinishBatchMove
                                )
                            )
                            movedCount += 1
                            try? await Task.sleep(for: .milliseconds(100))
                        } catch {
                            if case EventError.moveSuperseded = error {
                                finishSupersededApply(items: freshItems)
                                return
                            }
                            unenactedMoveCount += 1
                            MenuBarItemManager.diagLog.error(
                                "Profile layout: per-item move to AH failed for \(uid): \(error)"
                            )
                            enqueueApplyMoveFailure(
                                error,
                                item: item,
                                destination: .leftOfItem(ahItem),
                                expectedSection: .alwaysHidden
                            )
                        }
                    }

                    // Each move lands just right of AH_ctrl and pushes the rest right,
                    // so index 0 moves last. See crossSectionFallbackMoveOrder.
                    let hiddenProfileOrder = itemOrder["hidden"] ?? []
                    let orderedCrossToHidden = LayoutSolver.crossSectionFallbackMoveOrder(
                        profileOrder: hiddenProfileOrder,
                        crossing: crossToHidden,
                        landingSlot: .leftmostOfHidden
                    )
                    for uid in orderedCrossToHidden {
                        guard !Task.isCancelled else { break }
                        guard
                            let item = freshItems.first(where: { $0.uniqueIdentifier == uid && isProfileItem($0) })
                        else { continue }
                        do {
                            try await move(
                                item: item,
                                to: .rightOfItem(ahItem),
                                skipInputPause: true,
                                options: .init(
                                    shouldBegin: shouldBeginBatchMove,
                                    didFinishWhileHoldingGate: didFinishBatchMove
                                )
                            )
                            movedCount += 1
                            try? await Task.sleep(for: .milliseconds(100))
                        } catch {
                            if case EventError.moveSuperseded = error {
                                finishSupersededApply(items: freshItems)
                                return
                            }
                            unenactedMoveCount += 1
                            MenuBarItemManager.diagLog.error(
                                "Profile layout: per-item move to hidden failed for \(uid): \(error)"
                            )
                            enqueueApplyMoveFailure(
                                error,
                                item: item,
                                destination: .rightOfItem(ahItem),
                                expectedSection: .hidden
                            )
                        }
                    }
                }
            }
        }

        // ── Sub-phase 2: LCS for remaining item ordering ──
        //
        // Control item moves may have changed section assignments.
        if movedCount > 0 || didAttemptHCtrl {
            items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard shouldBeginBatchMove() else {
                finishSupersededApply(items: items)
                return
            }
            var itemsCopy2 = items
            guard let freshControl = ControlItemPair(
                items: &itemsCopy2,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems else {
                MenuBarItemManager.diagLog.error("applyProfileLayout: lost control items after phase 1")
                // Counts as unenacted: the LCS pass never ran.
                abandonApply(reason: nil, items: items)
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

        // Control items were handled above.
        // desiredFiltered, not desiredFlat, so unmanaged placement and notch
        // overflow are respected.
        let currentNoControls = currentFlat.filter { $0 != hiddenCtrlUID && $0 != ahCtrlUID }
        var desiredNoControls = desiredFiltered.filter { $0 != hiddenCtrlUID && $0 != ahCtrlUID }

        // Relaxed on the desired sequence, not the planned moves, or surviving
        // moves anchor on items the plan assumed had shifted. Sort A→Z enforces it.
        let enforceConcealedOrder = enforceConcealedSectionOrder
            || ((Defaults.object(forKey: .enforceConcealedSectionOrder) as? Bool)
                ?? Defaults.DefaultValue.enforceConcealedSectionOrder)
        if !enforceConcealedOrder {
            desiredNoControls = LayoutSolver.relaxConcealedSectionOrder(
                desiredNoControls: desiredNoControls,
                currentNoControls: currentNoControls,
                sectionMap: sectionMap
            )
        }

        // The chevron's position is persisted, so it stays in the order, but a failing
        // move anchored on our own items walks them across the bar (#924).
        let unanchorableUIDs = Set(
            items.lazy.filter(\.isControlItem).map(\.uniqueIdentifier)
        )

        let plannedMoves = LayoutSolver.planLCSMoveSequence(
            currentNoControls: currentNoControls,
            desiredNoControls: desiredNoControls,
            sectionMap: sectionMap,
            unanchorableUIDs: unanchorableUIDs,
            preferredMoveUIDs: Set(unmanagedUIDs)
        )

        guard !plannedMoves.isEmpty else {
            if movedCount > 0 {
                MenuBarItemManager.diagLog.info("Profile layout: completed with \(movedCount) control item move(s), no item reordering needed")
            } else {
                MenuBarItemManager.diagLog.info("Profile layout: all items already in correct positions")
            }
            // A divider that refused to move counts even with nothing left to plan.
            recordBulkApplyOutcome(unenactedMoveCount: unenactedMoveCount)
            concludeProfileApplyWithoutMoves(source: source, items: items)
            scheduleDeferredCacheRefresh()
            return
        }

        MenuBarItemManager.diagLog.info(
            "Profile layout: \(plannedMoves.count) item move(s) needed (\(movedCount) control move(s) preceded)"
        )

        // Failures with no success between them; feeds MoveCircuitBreaker.batchShouldAbandon.
        // Backoff skips don't count; they cost nothing and say nothing new.
        var consecutiveMoveFailures = 0

        for (plannedIndex, planned) in plannedMoves.enumerated() {
            // The newer apply owns the tally now.
            guard !Task.isCancelled else { break }

            if failureLedger.isUnderBackoff(key: planned.uid) {
                unenactedMoveCount += 1
                MenuBarItemManager.diagLog.warning(
                    "Profile layout: \(planned.uid) under move-failure backoff, skipping"
                )
                continue
            }

            let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard shouldBeginBatchMove() else {
                finishSupersededApply(items: allFreshItems)
                return
            }
            var freshItemsCopy = allFreshItems
            guard let freshControl = ControlItemPair(
                items: &freshItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems else {
                unenactedMoveCount += plannedMoves.count - plannedIndex
                break
            }

            guard let item = allFreshItems.first(where: {
                $0.uniqueIdentifier == planned.uid && isProfileItem($0)
            }) else {
                continue
            }

            // A missing anchor falls back to the target section's boundary.
            let fallbackSection = sectionName(for: sectionMap[planned.uid] ?? "visible") ?? .visible
            let dest = LayoutReconciler.resolveDestination(
                planned.destination,
                items: allFreshItems,
                controlItems: freshControl,
                fallbackSection: fallbackSection
            )

            // A visible-bound item anchored on a parked item gets stranded off screen,
            // and the next move chains off it (#1027). Concealed sections are
            // parked by design, so only visible-bound moves are gated.
            // Skipping counts as unenacted, which withholds the save.
            if fallbackSection == .visible {
                let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
                if dest.wouldLandOffScreen(screenFrames: screenFrames) {
                    unenactedMoveCount += 1
                    MenuBarItemManager.diagLog.warning(
                        "Profile layout: skipping the visible-bound move of \(planned.uid), its anchor \(dest.logString) is parked offscreen (minX=\(dest.targetItem.bounds.minX)); the drop would strand it"
                    )
                    continue
                }
            }

            do {
                try await move(
                    item: item,
                    to: dest,
                    skipInputPause: true,
                    options: .init(
                        shouldBegin: shouldBeginBatchMove,
                        didFinishWhileHoldingGate: didFinishBatchMove
                    )
                )
                movedCount += 1
                consecutiveMoveFailures = 0
                failureLedger.recordSuccess(for: item)
                try? await Task.sleep(for: .milliseconds(200))
            } catch {
                if case EventError.moveSuperseded = error {
                    finishSupersededApply(items: allFreshItems)
                    return
                }
                // Cancelled mid-move: the failure is the newer apply's takeover,
                // not the item's (#900).
                if Task.isCancelled {
                    MenuBarItemManager.diagLog.debug(
                        "Profile layout: move of \(planned.uid) interrupted by a newer apply; leaving it unrecorded"
                    )
                    break
                }
                unenactedMoveCount += 1
                consecutiveMoveFailures += 1
                if !Self.moveAlreadyFiledFailure(for: error) {
                    failureLedger.recordFailure(for: item, kind: Self.failureKind(of: error))
                }
                MenuBarItemManager.diagLog.error(
                    "Profile layout: failed to move \(planned.uid): \(error)"
                )
                enqueueApplyMoveFailure(
                    error,
                    item: item,
                    destination: dest,
                    expectedSection: fallbackSection
                )
                if MoveCircuitBreaker.batchShouldAbandon(consecutiveFailures: consecutiveMoveFailures) {
                    unenactedMoveCount += plannedMoves.count - plannedIndex - 1
                    MenuBarItemManager.diagLog.warning(
                        "Profile layout: \(consecutiveMoveFailures) consecutive move failures, abandoning the remaining \(plannedMoves.count - plannedIndex - 1) move(s)"
                    )
                    break
                }
            }
        }

        MenuBarItemManager.diagLog.info("Profile layout: completed with \(movedCount) move(s)")

        recordBulkApplyOutcome(unenactedMoveCount: unenactedMoveCount)

        // Last move has landed; nothing below touches the cursor.
        restoreCursor()

        // MARK: Phase 7: finalize (cursor, snapshot, cache, UI refresh)

        // No-op if Phase 6 already restored it.
        restoreCursor()

        // So late-arrival detection doesn't re-trigger for items we just sorted.
        items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        // A cancelled apply commits nothing: roll back (token-guarded) and let
        // the replacing apply schedule the refresh.
        if Task.isCancelled, case .profile = source {
            restoreProfileStateAfterAbortedApply(token: applyToken)
            return
        }
        // Cancellation breaks the move loop but still reaches Phase 7.
        if !Task.isCancelled {
            persistProfileStateOnSuccess(source: source)
        }
        clearProfileState(source: source, items: items)

        scheduleDeferredCacheRefresh()
    }

    /// Whether consecutive ControlItemPair lookup failures warrant rebuilding
    /// the status items (#754). The latch resets only after a successful
    /// lookup, so a permanent failure rebuilds at most once.
    static nonisolated func shouldRebuildControlItems(
        consecutiveFailures: Int,
        alreadyRebuilt: Bool = false,
        threshold: Int = MenuBarItemManager.controlItemRebuildThreshold
    ) -> Bool {
        !alreadyRebuilt && consecutiveFailures >= threshold
    }

    /// The wait a change-detector recache must respect while control-item
    /// lookups keep failing, or nil while no backoff applies.
    ///
    /// A permanent failure otherwise recaches every poll (#933). No wait below
    /// the rebuild threshold; past it the wait doubles up to maxDelay.
    /// Event-driven recaches bypass this.
    static nonisolated func controlItemLookupRetryBackoff(
        consecutiveFailures: Int,
        threshold: Int = MenuBarItemManager.controlItemRebuildThreshold,
        baseDelay: Duration = .seconds(6),
        maxDelay: Duration = .seconds(60)
    ) -> Duration? {
        guard consecutiveFailures >= threshold else {
            return nil
        }
        // Capped so a long streak can't overflow the shift.
        let exponent = min(consecutiveFailures - threshold, 6)
        return min(baseDelay * (1 << exponent), maxDelay)
    }

    /// Whether repeated authoritative cache cycles should reset an
    /// always-hidden divider that the feature enables but which does not
    /// resolve, while the hidden divider resolves fine.
    static nonisolated func shouldRecoverMissingAlwaysHiddenDivider(
        consecutiveMissingReadings: Int,
        alreadyRecovered: Bool = false,
        threshold: Int = MenuBarItemManager.missingAlwaysHiddenDividerRecoveryThreshold
    ) -> Bool {
        !alreadyRecovered && consecutiveMissingReadings >= threshold
    }

    /// Whether a persistent zero-width hidden span has enough trustworthy
    /// observations to reset the hidden divider once for this episode.
    static nonisolated func shouldRecoverCollapsedHiddenSection(
        consecutiveCollapsedReadings: Int,
        alreadyRecovered: Bool = false,
        threshold: Int = MenuBarItemManager.hiddenSectionCollapseRecoveryThreshold
    ) -> Bool {
        !alreadyRecovered && consecutiveCollapsedReadings >= threshold
    }

    /// Whether repeated authoritative mismatch applies should reset a hidden
    /// divider that remains parked off every display.
    static nonisolated func shouldRecoverParkedHiddenDivider(
        consecutiveMismatchReadings: Int,
        alreadyRecovered: Bool = false,
        threshold: Int = MenuBarItemManager.parkedHiddenDividerRecoveryThreshold
    ) -> Bool {
        !alreadyRecovered && consecutiveMismatchReadings >= threshold
    }

    /// Whether a divider rebuild may also re-stamp the first-launch seed
    /// position.
    ///
    /// The fresh-install seed on a populated bar drops the divider beside every
    /// item, collapsing the bar into one section (#895, #958). Recreating the
    /// status item is what matters; the follow-up apply places it.
    static nonisolated func canSeedRebuiltDividerPosition(managedItemCount: Int) -> Bool {
        managedItemCount == 0
    }

    /// The stored NSStatusItem preferred positions of the three control
    /// items, as a divider rebuild reads them back off ControlItemDefaults.
    ///
    /// Larger means further left; healthy is visible < hidden < alwaysHidden.
    /// nil means nothing is stored (e.g. a disabled always-hidden section).
    nonisolated struct StoredDividerPositions {
        let visible: CGFloat?
        let hidden: CGFloat?
        let alwaysHidden: CGFloat?
    }

    /// Whether the stored hidden-divider position still describes a bar the
    /// divider can be rebuilt onto.
    ///
    /// macOS can autosave an inverted order, which survives relaunch as a
    /// zero-width hidden section (#978). Unknown bounds pass.
    static nonisolated func storedHiddenPositionIsOrdered(_ positions: StoredDividerPositions) -> Bool {
        guard let hidden = positions.hidden else { return true }
        if let visible = positions.visible, hidden <= visible {
            return false
        }
        if let alwaysHidden = positions.alwaysHidden, hidden >= alwaysHidden {
            return false
        }
        return true
    }

    /// A stored position to replace an inverted one with, or nil when the
    /// neighbours give nothing to place the divider between.
    ///
    /// Restores ordering, not geometry; the following apply places the divider.
    static nonisolated func repairedHiddenDividerPosition(
        _ positions: StoredDividerPositions
    ) -> CGFloat? {
        switch (positions.visible, positions.alwaysHidden) {
        case let (visible?, alwaysHidden?):
            // Both neighbours are corrupt too; a midpoint would be just as wrong.
            guard alwaysHidden > visible else { return nil }
            return (visible + alwaysHidden) / 2
        case let (visible?, nil):
            return visible + 1
        case let (nil, alwaysHidden?):
            return alwaysHidden - 1
        case (nil, nil):
            return nil
        }
    }

    /// What a divider rebuild should do with the stored preferred position.
    nonisolated enum RebuiltDividerSeed: Equatable {
        /// Stamp the value ControlItem.preflightSetup writes on a fresh
        /// install. Only for a bar with no managed items.
        case freshInstall(CGFloat)
        /// Rebuild without touching the stored position.
        case keepStored
        /// Stamp a replacement because the stored position is inverted.
        case repaired(CGFloat)

        /// The value to hand ControlItem.recreateStatusItem, or nil to
        /// leave the stored position alone.
        var preferredPosition: CGFloat? {
            switch self {
            case let .freshInstall(position): position
            case .keepStored: nil
            case let .repaired(position): position
            }
        }
    }

    /// What a divider rebuild should stamp, given the bar it is rebuilding
    /// onto and the positions currently on disk.
    ///
    /// - An empty bar takes the fresh-install seed.
    /// - A populated, correctly ordered bar keeps its stored position.
    /// - An inverted one gets a repaired position; keeping it survived relaunch (#978).
    static nonisolated func seedForRebuiltDivider(
        managedItemCount: Int,
        storedPositions: StoredDividerPositions
    ) -> RebuiltDividerSeed {
        if canSeedRebuiltDividerPosition(managedItemCount: managedItemCount) {
            return .freshInstall(1)
        }
        guard !storedHiddenPositionIsOrdered(storedPositions),
              let repaired = repairedHiddenDividerPosition(storedPositions)
        else {
            return .keepStored
        }
        return .repaired(repaired)
    }

    /// Reads the stored control item positions a divider rebuild plans
    /// against.
    @MainActor
    static func currentStoredDividerPositions() -> StoredDividerPositions {
        StoredDividerPositions(
            visible: ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue],
            hidden: ControlItemDefaults[.preferredPosition, ControlItem.Identifier.hidden.rawValue],
            alwaysHidden: ControlItemDefaults[
                .preferredPosition,
                ControlItem.Identifier.alwaysHidden.rawValue
            ]
        )
    }

    /// Names the rebuild branch that ran, for field logs.
    static nonisolated func seedDescription(_ seed: RebuiltDividerSeed) -> String {
        switch seed {
        case let .freshInstall(position):
            " at its seeded position (\(position))"
        case .keepStored:
            " and keeping its stored position (the bar holds managed items)"
        case let .repaired(position):
            " at a repaired position (\(position)); the stored one ordered H_ctrl outside its neighbours"
        }
    }

    static nonisolated func baseIdentifier(forSavedIdentifier identifier: String) -> String {
        let parts = identifier.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return identifier }
        return "\(parts[0]):\(parts[1])"
    }

    static nonisolated func savedLayoutSectionLookup(
        savedSectionOrder: [String: [String]]
    ) -> (
        exact: [String: MenuBarSection.Name],
        unambiguousBase: [String: MenuBarSection.Name]
    ) {
        var exactSections = [String: Set<MenuBarSection.Name>]()
        var baseSections = [String: Set<MenuBarSection.Name>]()

        for (sectionKey, identifiers) in savedSectionOrder {
            guard let section = persistedSectionName(for: sectionKey) else { continue }
            for identifier in identifiers {
                exactSections[identifier, default: []].insert(section)
                baseSections[baseIdentifier(forSavedIdentifier: identifier), default: []].insert(section)
            }
        }

        let exact = exactSections.compactMapValues { sections in
            sections.count == 1 ? sections.first : nil
        }
        let unambiguousBase = baseSections.compactMapValues { sections in
            sections.count == 1 ? sections.first : nil
        }

        return (exact, unambiguousBase)
    }

    /// Whether any saved, movable item is in a different section than saved.
    ///
    /// Catches drift that keeps windowIDs (Stage Manager, third-party tools,
    /// macOS respawning the bar). Straddling items are ignored during show/hide
    /// animations; base-identifier fallback applies only when all saved
    /// instances share one section.
    private func currentLayoutDivergesFromSaved(
        items: [MenuBarItem],
        controlItems: ControlItemPair
    ) -> Bool {
        // Ejected items diverge by design and would re-dispatch every cycle. Skip
        // them only with the feature on, a notched active display, and the item in hidden.
        let overflowSkipActive = (appState?.settings.advanced.enableMenuBarItemOverflow ?? false)
            && ((NSScreen.screenWithActiveMenuBar ?? NSScreen.main)?.hasNotch ?? false)
        let knownBaseIdentifiers = Set(items.map(\.tag.stableIdentifierBase))
        let knownLiveIdentifiers = Set(items.map(\.uniqueIdentifier))
        // With no triggers, isTriggerProtected goes quadratic on a per-cycle path.
        let hasTriggerProtectedItems = !triggerControlledItemIdentifiers.isEmpty

        return Self.layoutDivergesFromSaved(
            candidates: items
                .filter {
                    !$0.isControlItem
                        && $0.canBeHidden
                        && $0.isMovable
                        && !(hasTriggerProtectedItems && Self.isTriggerProtected(
                            $0.uniqueIdentifier,
                            by: triggerControlledItemIdentifiers,
                            knownBaseIdentifiers: knownBaseIdentifiers,
                            knownLiveIdentifiers: knownLiveIdentifiers
                        ))
                }
                .map { item in
                    DivergenceCandidate(
                        tagIdentifier: item.tag.tagIdentifier,
                        uniqueIdentifier: item.uniqueIdentifier,
                        bounds: item.bounds
                    )
                },
            sectionLookup: Self.savedLayoutSectionLookup(savedSectionOrder: savedSectionOrder),
            hiddenBounds: controlItems.hidden.bounds,
            alwaysHiddenBounds: controlItems.alwaysHidden?.bounds,
            overflowExemptUIDs: overflowSkipActive ? notchOverflowEjectedUIDs : [],
            activelyShownTags: Set(temporarilyShownItemContexts.map(\.tag.tagIdentifier))
        )
    }

    /// One item of a bar reading, reduced to what the divergence rule reads.
    struct DivergenceCandidate {
        let tagIdentifier: String
        let uniqueIdentifier: String
        let bounds: CGRect
    }

    /// Whether any item sits in a different section than savedSectionOrder
    /// records for it.
    ///
    /// applySavedLayout's drift trigger. Exemptions are passed in to keep it pure:
    ///
    /// - overflowExemptUIDs: notch ejections; empty unless the feature is on
    ///   and the active display is notched.
    /// - activelyShownTags: temporarily shown items. Treating them as drift can
    ///   drag one home under the menu the user just opened (#924).
    static nonisolated func layoutDivergesFromSaved(
        candidates: [DivergenceCandidate],
        sectionLookup: (exact: [String: MenuBarSection.Name], unambiguousBase: [String: MenuBarSection.Name]),
        hiddenBounds: CGRect,
        alwaysHiddenBounds: CGRect?,
        overflowExemptUIDs: Set<String>,
        activelyShownTags: Set<String>
    ) -> Bool {
        guard !sectionLookup.exact.isEmpty || !sectionLookup.unambiguousBase.isEmpty else { return false }

        let hiddenMinX = hiddenBounds.minX
        let hiddenMaxX = hiddenBounds.maxX
        let ahBounds = alwaysHiddenBounds

        for candidate in candidates {
            guard !activelyShownTags.contains(candidate.tagIdentifier) else { continue }
            let identifier = candidate.uniqueIdentifier
            let baseID = Self.baseIdentifier(forSavedIdentifier: identifier)
            guard let expectedSection = sectionLookup.exact[identifier]
                ?? sectionLookup.unambiguousBase[baseID]
            else {
                continue
            }

            let currentSection: MenuBarSection.Name? = if candidate.bounds.minX >= hiddenMaxX {
                .visible
            } else if let ahBounds, candidate.bounds.maxX <= ahBounds.minX {
                .alwaysHidden
            } else if let ahBounds, candidate.bounds.minX >= ahBounds.maxX, candidate.bounds.maxX <= hiddenMinX {
                .hidden
            } else if ahBounds == nil, candidate.bounds.maxX <= hiddenMinX {
                .hidden
            } else {
                nil
            }

            guard let currentSection else { continue }
            if currentSection == .hidden, overflowExemptUIDs.contains(identifier) {
                continue
            }
            if currentSection != expectedSection {
                return true
            }
        }
        return false
    }

    /// Whether a windowID-set difference is a real change or just the menu bar
    /// switching displays.
    ///
    /// With separate Spaces, a display switch makes the old display's windows
    /// read as missing. Treating that as a quit re-sorts on every focus change.
    static nonisolated func windowIDsChanged(
        previous: Set<CGWindowID>,
        current: Set<CGWindowID>,
        previousDisplayID: CGDirectDisplayID?,
        currentDisplayID: CGDirectDisplayID?
    ) -> Bool {
        guard !previous.isEmpty else { return false }
        // Only when both displays are known and differ.
        if let previousDisplayID, let currentDisplayID, previousDisplayID != currentDisplayID {
            return false
        }
        return !previous.isSubset(of: current)
    }

    /// Whether enough menu bar items are missing a resolved source PID that
    /// bulk-applying the saved layout would act on unmatchable identities.
    ///
    /// A failed XPC connection leaves most items with a nil sourcePID. Some
    /// system items are always nil, so only a majority counts; tiny sets are exempt.
    static nonisolated func majorityOfSourcePIDsUnresolved(unresolvedCount: Int, itemCount: Int) -> Bool {
        itemCount >= 4 && unresolvedCount * 2 > itemCount
    }

    /// The profile's items that have appeared since the last profile sort,
    /// and so warrant a re-sort.
    ///
    /// Unresolved and misattributed items (#1027) are excluded: their fallback
    /// identity flaps between spellings, and each flap reads as a new arrival (#881).
    /// Items with a legitimately nil PID never arrive late anyway.
    static nonisolated func lateArrivingProfileIdentifiers(
        items: [MenuBarItem],
        profileIdentifiers: Set<String>,
        alreadySortedIdentifiers: Set<String>
    ) -> Set<String> {
        let identifiable = Set(
            items.lazy
                .filter {
                    !$0.isControlItem && $0.sourcePID != nil && !$0.tag.isMisattributedControlCenterModule
                }
                .map(\.uniqueIdentifier)
        )
        return identifiable
            .intersection(profileIdentifiers)
            .subtracting(alreadySortedIdentifiers)
    }

    /// Narrows a saved order to the identifiers whose live item has a
    /// resolved sourcePID, for the early apply that runs while resolution is
    /// still in progress.
    ///
    /// A dropped identifier stays untouched, since planLCSMoveSequence only moves
    /// items in both sequences. Empty section keys are kept.
    ///
    /// Exact match: a base match could admit an unresolved sibling (Item-0:2).
    static nonisolated func savedOrderRestrictedToResolvedIdentities(
        savedSectionOrder: [String: [String]],
        resolvedIdentifiers: Set<String>
    ) -> [String: [String]] {
        savedSectionOrder.mapValues { identifiers in
            identifiers.filter(resolvedIdentifiers.contains)
        }
    }

    /// Decides whether a divergence observation should trigger the apply.
    ///
    /// A wide app menu can shift status items for a moment, so divergence must
    /// be seen on two consecutive cycles (#723).
    ///
    /// - Parameters:
    ///   - divergedNow: The result of the current cycle's divergence check.
    ///   - pendingSince: The timestamp of a prior unconfirmed observation, if
    ///     one is armed.
    ///   - now: The current time.
    ///   - staleness: How long an armed observation can still be confirmed.
    ///     A stale arm is treated as a fresh first observation.
    /// - Returns: Whether this confirms the divergence, and the pending
    ///   state for the next cycle.
    static nonisolated func confirmedDivergence(
        divergedNow: Bool,
        pendingSince: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        staleness: Duration = .seconds(30)
    ) -> (confirmed: Bool, newPendingSince: ContinuousClock.Instant?) {
        guard divergedNow else {
            return (false, nil)
        }
        guard let pendingSince else {
            return (false, now)
        }
        guard now - pendingSince <= staleness else {
            // Too old to confirm against; re-arm.
            return (false, now)
        }
        return (true, nil)
    }

    /// Whether a bulk apply that left moves unenacted should still hold
    /// the saveSectionOrder gate shut.
    ///
    /// Never expires, or the failed batch gets saved (#900). A clean apply or a
    /// user move clears it.
    static nonisolated func unfinishedMoveBatchBlocksSave(
        observedAt: ContinuousClock.Instant?
    ) -> Bool {
        observedAt != nil
    }

    /// The idle window an automatic bulk apply should wait for, or nil
    /// when the gate is switched off.
    ///
    /// A non-positive threshold switches it off. A negative cap is clamped so a
    /// defaults typo means "don't wait", not "never start".
    static nonisolated func bulkApplyIdleWindow(
        thresholdMs: Int,
        capMs: Int
    ) -> (threshold: Duration, cap: Duration)? {
        guard thresholdMs > 0 else { return nil }
        return (.milliseconds(thresholdMs), .milliseconds(max(0, capMs)))
    }

    nonisolated enum BulkApplyIdleWaitDecision: Equatable {
        case waiting
        case ready
        case deferBatch
    }

    /// Whether an automatic bulk apply may start, must keep waiting, or should
    /// defer this dispatch. The cap is never permission to override input.
    static nonisolated func bulkApplyIdleWaitDecision(
        userHasPausedInput: Bool,
        elapsed: Duration,
        cap: Duration
    ) -> BulkApplyIdleWaitDecision {
        if userHasPausedInput {
            return .ready
        }
        if elapsed >= cap {
            return .deferBatch
        }
        return .waiting
    }

    /// Batches yield only between complete gestures, after the previous mouse-up.
    static nonisolated func automaticBatchShouldYieldForInput(
        automatic: Bool,
        userHasPausedPhysicalInput: Bool
    ) -> Bool {
        automatic && !userHasPausedPhysicalInput
    }

    /// The previous cache cycle's state that applySavedLayout diffs
    /// the current bar against to decide whether a restore is warranted.
    nonisolated struct PreviousCacheCycle {
        var windowIDs: [CGWindowID]
        var displayID: CGDirectDisplayID?
        var ccGenericWindowIDs: Set<CGWindowID> = []
    }

    /// Re-applies the saved layout through applyProfileLayout with source .savedOrder.
    ///
    /// Returns true if dispatched; the apply drives its own recache, so the
    /// caller should stop its cycle. False when an entry guard rejects it.
    func applySavedLayout(
        items: [MenuBarItem],
        previousCycle: PreviousCacheCycle,
        controlItems: ControlItemPair,
        currentDisplayID: CGDirectDisplayID? = nil,
        bypassMoveCooldown: Bool = false,
        resolvedIdentitiesOnly: Bool = false,
        shouldBegin: (@MainActor () -> Bool)? = nil
    ) async -> Bool {
        guard shouldBegin?() ?? true else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping superseded cache snapshot")
            return false
        }
        // Each guard logs a distinct reason for bug reports. Cheap checks first.
        guard !savedSectionOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, savedSectionOrder is empty")
            return false
        }
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping for provisional AX-frame correlation"
            )
            return false
        }
        guard !suppressNextNewLeftmostItemRelocation else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, suppressNextNewLeftmostItemRelocation armed")
            return false
        }
        guard !isApplyingProfileLayout else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, profile apply in flight")
            return false
        }
        // Prevents cascading re-applies when many apps relaunch together.
        // The launch restore bypasses it: its own chain just stamped it and there's no retry (#881).
        guard bypassMoveCooldown || !lastMoveOperationOccurred(within: .seconds(5)) else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, within 5s move cooldown")
            return false
        }
        // Not bypassable: this reads the history of unfinished applies.
        guard isAutomaticBulkApplyPermitted(caller: "applySavedLayout") else {
            return false
        }

        // Change gate, since this runs every tick. Two signals pass it:
        //
        // 1. windowIDsChanged: an item disappeared (quit or relaunch). Additions
        //    belong to relocateNewLeftmostItems; recycled window IDs aren't covered.
        // 2. layoutDiverged: a saved item is in another section. Catches drift
        //    with stable windowIDs, and cold boot for non-profile users.
        //
        // Divergence is only computed when needed, and must be seen twice (#723).
        // windowIDsChanged is trustworthy and stays immediate.
        let currentWindowIDSet = Set(items.map(\.windowID))
        let previousWindowIDSet = Set(previousCycle.windowIDs)
        // Control Center Item-N windows churn IDs (Live Activities). They're never
        // saved, so ignoring them misses nothing (#736).
        let windowIDsChanged = Self.windowIDsChanged(
            previous: previousWindowIDSet.subtracting(previousCycle.ccGenericWindowIDs),
            current: currentWindowIDSet,
            previousDisplayID: previousCycle.displayID,
            currentDisplayID: currentDisplayID
        )
        let layoutDiverged: Bool
        if windowIDsChanged {
            layoutDiverged = false
        } else {
            let divergedNow = currentLayoutDivergesFromSaved(items: items, controlItems: controlItems)
            let now = ContinuousClock.now
            let decision = Self.confirmedDivergence(
                divergedNow: divergedNow,
                pendingSince: pendingDivergenceObservedAt,
                now: now
            )
            pendingDivergenceObservedAt = decision.newPendingSince
            if divergedNow, !decision.confirmed {
                MenuBarItemManager.diagLog.debug("applySavedLayout: divergence observed, awaiting confirmation on next cycle")
            } else if decision.confirmed {
                MenuBarItemManager.diagLog.debug("applySavedLayout: divergence confirmed on second consecutive cycle")
            }
            layoutDiverged = decision.confirmed
        }
        guard windowIDsChanged || layoutDiverged else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no windowID change and saved layout matches current")
            return false
        }
        // Discard the arm so it can't confirm a later, unrelated cycle.
        pendingDivergenceObservedAt = nil

        // resolvedIdentitiesOnly callers are exempt; they only touch resolved identities.
        let unresolvedSourcePIDCount = items.count { $0.sourcePID == nil }
        if !resolvedIdentitiesOnly,
           Self.majorityOfSourcePIDsUnresolved(unresolvedCount: unresolvedSourcePIDCount, itemCount: items.count)
        {
            MenuBarItemManager.diagLog.info(
                "applySavedLayout: skipping, \(unresolvedSourcePIDCount)/\(items.count) items have unresolved sourcePIDs (XPC resolution likely failed)"
            )
            return false
        }

        // A synthetic Cmd-drag would tear down an open menu. The gate stays armed.
        let menuIsOpen = await isAnyMenuBarItemMenuOpen()
        guard shouldBegin?() ?? true else {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping, a user move superseded the snapshot during the menu check"
            )
            return false
        }
        if menuIsOpen {
            MenuBarItemManager.diagLog.info("applySavedLayout: skipping, a menu bar item menu is open")
            return false
        }

        // Skip if no saved item is present. Base-identifier matches count only
        // when all instances share a section (Item-0:1 visible, Item-0:2 hidden doesn't).
        let sectionLookup = Self.savedLayoutSectionLookup(savedSectionOrder: savedSectionOrder)
        let currentIdentifiers = Set(items.map(\.uniqueIdentifier))
        let currentBaseIdentifiers = Set(items.map { Self.baseIdentifier(forSavedIdentifier: $0.uniqueIdentifier) })
        guard !Set(sectionLookup.exact.keys).isDisjoint(with: currentIdentifiers)
            || !Set(sectionLookup.unambiguousBase.keys).isDisjoint(with: currentBaseIdentifiers)
        else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no saved items currently present")
            return false
        }

        // Under resolvedIdentitiesOnly, unidentified items are left untouched;
        // the settling-end pass moves the remainder.
        var effectiveSavedOrder: [String: [String]]
        if resolvedIdentitiesOnly {
            effectiveSavedOrder = Self.savedOrderRestrictedToResolvedIdentities(
                savedSectionOrder: savedSectionOrder,
                resolvedIdentifiers: Set(
                    items.lazy.filter { $0.sourcePID != nil }.map(\.uniqueIdentifier)
                )
            )
            guard effectiveSavedOrder.values.contains(where: { !$0.isEmpty }) else {
                MenuBarItemManager.diagLog.debug(
                    "applySavedLayout: skipping, no saved items have resolved identities yet"
                )
                return false
            }
        } else {
            effectiveSavedOrder = savedSectionOrder
        }
        let knownBaseIdentifiers = Set(items.map(\.tag.stableIdentifierBase))
        let knownLiveIdentifiers = Set(items.map(\.uniqueIdentifier))
        effectiveSavedOrder = Self.savedOrderExcludingTriggerControlledIdentifiers(
            effectiveSavedOrder,
            controlledIdentifiers: triggerControlledItemIdentifiers,
            knownBaseIdentifiers: knownBaseIdentifiers,
            knownLiveIdentifiers: knownLiveIdentifiers
        )
        guard effectiveSavedOrder.values.contains(where: { !$0.isEmpty }) else {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping, every saved item is currently trigger-controlled"
            )
            return false
        }

        var itemSectionMap = [String: String]()
        for (sectionKey, identifiers) in effectiveSavedOrder {
            for identifier in identifiers {
                itemSectionMap[identifier] = sectionKey
            }
        }

        let trigger = if windowIDsChanged {
            "windowID change"
        } else if resolvedIdentitiesOnly {
            "layout divergence, resolved identities only"
        } else {
            "layout divergence"
        }

        // Refuse what the save path refuses. Collapsed dividers misread hidden as
        // visible, and the drags would then let the damage be saved (#868).
        let hiddenSectionHasRoom = LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: controlItems.hidden.bounds.minX,
            alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX,
            savedHiddenItemCount: effectiveSavedOrder[sectionKey(for: .hidden)]?.count ?? 0,
            // From the items passed in; no recache has run yet.
            liveHiddenItemCount: LayoutSolver.liveHiddenItemCount(
                itemBounds: items.map(\.bounds),
                hiddenControlItemMinX: controlItems.hidden.bounds.minX,
                alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX
            ),
            hasVisibleItemParkedOffBar: LayoutSolver.hasVisibleItemParkedOffBar(
                itemBounds: items.map(\.bounds),
                hiddenControlItemMinX: controlItems.hidden.bounds.minX,
                screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
            )
        )
        guard hiddenSectionHasRoom else {
            MenuBarItemManager.diagLog.warning(
                "applySavedLayout: skipping (\(trigger)); hidden section has zero width between the dividers (hidden.minX=\(controlItems.hidden.bounds.minX) windowID=\(controlItems.hidden.windowID), alwaysHidden.maxX=\(controlItems.alwaysHidden?.bounds.maxX.description ?? "nil") windowID=\(controlItems.alwaysHidden?.windowID.description ?? "nil"))"
            )
            recoverStrandedHiddenDividerBeforeRefusing(
                guardSource: "applySavedLayout",
                controlItems: controlItems,
                items: items
            )
            return false
        }

        // Divider-order gate (#1027), same as the profile path.
        let dividerBounds = dividerControlItemBounds(items: items, controlItems: controlItems)
        guard LayoutSolver.controlItemsAreInCanonicalOrder(
            visibleControlItemBounds: dividerBounds.visible,
            hiddenControlItemBounds: dividerBounds.hidden,
            alwaysHiddenControlItemBounds: dividerBounds.alwaysHidden
        ) else {
            MenuBarItemManager.diagLog.warning(
                "applySavedLayout: skipping (\(trigger)); section dividers are out of order (visibleCtrl.minX=\(dividerBounds.visible?.minX.description ?? "unresolved"), hidden.minX=\(dividerBounds.hidden.minX), alwaysHiddenCtrl.minX=\(dividerBounds.alwaysHidden?.minX.description ?? "unresolved"))"
            )
            recoverStrandedHiddenDividerBeforeRefusing(
                guardSource: "applySavedLayout",
                controlItems: controlItems,
                items: items
            )
            await recoverMisplacedVisibleControlItem(
                controlItems: controlItems,
                items: items
            )
            return false
        }

        // Display-spread gate: macOS migrates windows between displays async, and
        // moves made mid-migration strand items on the wrong screen. CG frames.
        //
        // Only items right of the hidden divider; parked items' negative x can land
        // on a display left of main. Must match the saveSectionOrder gate.
        let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        let unparkedCenters = items
            .filter { $0.bounds.minX >= controlItems.hidden.bounds.minX }
            .map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
        if LayoutSolver.itemsSpanMultipleDisplays(itemCenters: unparkedCenters, screenFrames: screenFrames) {
            MenuBarItemManager.diagLog.warning(
                "applySavedLayout: skipping (\(trigger)); menu bar items span multiple displays (relocation in progress)"
            )
            return false
        }

        MenuBarItemManager.diagLog.info("applySavedLayout: dispatching bulk apply (\(trigger))")

        guard shouldBegin?() ?? true else {
            MenuBarItemManager.diagLog.debug(
                "applySavedLayout: skipping, a user move superseded the snapshot before dispatch"
            )
            return false
        }

        // Pinning comes from existing state; savedSectionOrder has none.
        // resolvedIdentitiesOnly doubles as duringSettling: its gate-holding caller
        // can't survive Phase 0's settling wait (#943).
        guard let batchLease = beginLayoutBatch(.savedRestore) else {
            return false
        }
        defer { finishLayoutBatch(batchLease) }

        let completionGenerationBeforeApply = bulkApplyCompletionGeneration
        let restorationIdentifiersAtDispatch = triggerLayoutRestorationItemIdentifiers
        // One-shot from sortSection's no-active-profile branch: honour the
        // sorted concealed-section order this apply instead of relaxing it.
        let enforceConcealed = enforceConcealedSectionOrderOnNextSavedApply
        enforceConcealedSectionOrderOnNextSavedApply = false
        await applyProfileLayout(
            ProfileLayoutSpec(
                pinnedHidden: pinnedHiddenBundleIDs,
                pinnedAlwaysHidden: pinnedAlwaysHiddenBundleIDs,
                sectionOrder: effectiveSavedOrder,
                itemSectionMap: itemSectionMap,
                itemOrder: effectiveSavedOrder
            ),
            source: .savedOrder,
            automatic: true,
            duringSettling: resolvedIdentitiesOnly,
            enforceConcealedSectionOrder: enforceConcealed,
            shouldBegin: {
                self.layoutBatchIsCurrent(batchLease) && (shouldBegin?() ?? true)
            }
        )
        // The completed-apply counter, not the shared one: a user drag landing in
        // between zeroes the shared counter and would clear the shields wrongly.
        if bulkApplyCompletionGeneration != completionGenerationBeforeApply,
           lastCompletedBulkApplyUnenactedMoveCount == 0
        {
            // Re-read: a gained or lost same-title sibling makes stale counts
            // clear the shield of an item the trigger still controls.
            let postApplyItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            let postApplyBaseIdentifiers = Set(postApplyItems.map(\.tag.stableIdentifierBase))
            let postApplyLiveIdentifiers = Set(postApplyItems.map(\.uniqueIdentifier))
            let restored = restorationIdentifiersAtDispatch.filter { identifier in
                LayoutSolver.savedPositionByBaseID(for: identifier, in: effectiveSavedOrder) != nil
                    && !Self.isTriggerProtected(
                        identifier,
                        by: triggerControlledItemIdentifiers,
                        knownBaseIdentifiers: postApplyBaseIdentifiers,
                        knownLiveIdentifiers: postApplyLiveIdentifiers
                    )
            }
            triggerLayoutRestorationItemIdentifiers.subtract(restored)
            if !restored.isEmpty {
                MenuBarItemManager.diagLog.debug(
                    "Cleared \(restored.count) trigger release restoration shield(s) after a clean saved-layout apply"
                )
            }
        }
        return true
    }

    /// On termination, moves items stuck at x=-1 back to visible, or Control
    /// Center's preferences keep them stuck. Normally hidden items are left alone.
    ///
    /// - Returns: The number of items that failed to move.
    @MainActor
    func restoreBlockedItemsToVisible() async -> Int {
        MenuBarItemManager.diagLog.info("Checking for blocked items (x=-1) to restore before app termination")

        guard let appState else {
            MenuBarItemManager.diagLog.error("Cannot restore items: missing appState")
            return 0
        }

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        let blockedItems = items.filter { item in
            guard item.isMovable, !item.isControlItem else { return false }
            let bounds = item.liveBounds
            return bounds.origin.x == -1
        }

        guard !blockedItems.isEmpty else {
            MenuBarItemManager.diagLog.debug("No blocked items found - skipping restoration")
            return 0
        }

        MenuBarItemManager.diagLog.warning("Found \(blockedItems.count) blocked items at x=-1, attempting to restore")

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
        ), controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.error("Cannot restore items: unable to find hidden control item")
            return blockedItems.count
        }

        var failedMoves = 0

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        for item in blockedItems {
            do {
                try await move(
                    item: item,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true,
                    options: .init(watchdogTimeout: Self.layoutWatchdogTimeout)
                )
                MenuBarItemManager.diagLog.info("Successfully restored blocked item \(item.logString) to visible section")
            } catch {
                failedMoves += 1
                MenuBarItemManager.diagLog.error("Failed to restore blocked item \(item.logString): \(error)")
            }
        }

        MenuBarItemManager.diagLog.info("Restore completed: \(blockedItems.count - failedMoves)/\(blockedItems.count) blocked items restored")

        try? await Task.sleep(for: .milliseconds(200))

        return failedMoves
    }
}
