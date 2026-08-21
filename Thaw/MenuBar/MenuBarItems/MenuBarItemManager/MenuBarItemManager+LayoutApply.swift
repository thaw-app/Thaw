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
    /// Errors that can occur during a layout reset.
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

    /// Resets menu bar layout data to a fresh-install state and moves all
    /// movable, hideable items (except the Thaw icon) to the
    /// Hidden section.
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
                ), retryControlItems.canRepositionControlItems {
                    guard !target.requiresAlwaysHiddenDivider || retryControlItems.alwaysHidden != nil else {
                        throw LayoutResetError.missingControlItems
                    }
                    MenuBarItemManager.diagLog.info("Recovered hidden section control item after re-enabling always-hidden section")
                    prepareLayoutStateForReset()
                    await enforceControlItemOrder(controlItems: retryControlItems)
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

        // Mutate authoritative layout state only after divider identity is
        // authoritative; a provisional lookup must leave the saved layout intact.
        prepareLayoutStateForReset()

        await enforceControlItemOrder(controlItems: controlItems)

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
        // A reset starts from no verdicts: surviving retirements would keep
        // pruning identifiers out of a layout the user just asked to rebuild.
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
                        watchdogTimeout: Self.layoutWatchdogTimeout
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

        // Give macOS a moment to settle after the first pass.
        try? await Task.sleep(for: .milliseconds(200))

        // Re-fetch and retry only items that are not yet in the target section.
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
            // Watchdog: guarantee this continuation is resumed even if the
            // cache call above bails before reaching the serialization gate
            // (in which case it never takes ownership of the waiter and the
            // defer in cacheItemsRegardless never fires for this token) or
            // if the nested recache Task it hands off to never runs because
            // `self` was deallocated first. Whichever side removes the token
            // from the waiter table first owns the resume; the other is a
            // no-op.
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

        // `appState` is now `@Observable` (wave 4), so the manual
        // `objectWillChange.send()` poke that used to force views bound to
        // `appState` to refresh after the async `imageCache` mutations above
        // is no longer needed: Observation tracks each mutated property
        // (`imageCache`'s own storage) directly, independent of this poke.

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
    func scheduleProfileResort() {
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

            // Same gate `applySavedLayout` consults, for the same reason.
            // This dispatch already feeds the streak through
            // `recordBulkApplyOutcome`, but until now nothing read it here,
            // so a bar whose batches never complete re-sorted on every
            // late arrival forever. In #899 that ran seven passes in 22
            // seconds — each one a full move batch with the cursor
            // hijacked — until the reporter killed the app.
            //
            // A late-arrival re-sort is automatic, so it belongs under the
            // gate. User-initiated applies still bypass it: `applyProfile`
            // calls `applyProfileLayout` directly and never comes through
            // here.
            guard self.isAutomaticBulkApplyPermitted(caller: "Profile re-sort") else {
                self.profileResortTask = nil
                return
            }

            MenuBarItemManager.diagLog.info("Profile re-sort: re-applying layout for late-arriving items")
            // Clear profileResortTask BEFORE calling applyProfileLayout,
            // because applyProfileLayout cancels profileResortTask to
            // prevent concurrent re-sorts; which would cancel THIS task
            // and cause the move loop to exit via Task.isCancelled.
            self.profileResortTask = nil
            await self.applyProfileLayout(
                ProfileLayoutSpec(
                    pinnedHidden: layout.pinnedHidden,
                    pinnedAlwaysHidden: layout.pinnedAlwaysHidden,
                    sectionOrder: layout.sectionOrder,
                    itemSectionMap: layout.itemSectionMap,
                    itemOrder: layout.itemOrder
                ),
                automatic: true
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
    /// The five pieces of a layout spec that every apply carries together:
    /// the pinning sets, the per-section order, and the two identifier maps
    /// derived from it.
    nonisolated struct ProfileLayoutSpec {
        let pinnedHidden: Set<String>
        let pinnedAlwaysHidden: Set<String>
        let sectionOrder: [String: [String]]
        let itemSectionMap: [String: String]
        let itemOrder: [String: [String]]
    }

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
    func armProfileState(
        source: ApplySource,
        pinnedHidden: Set<String>,
        pinnedAlwaysHidden: Set<String>,
        sectionOrder: [String: [String]],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) {
        guard case .profile = source else { return }

        // Snapshot the displaced state before overwriting so a cancelled
        // apply can roll back to what disk still holds (persistence is
        // deferred to persistProfileStateOnSuccess). The token pins the
        // snapshot to this apply: once a newer apply re-arms, the
        // displaced apply no longer owns the state and must not restore.
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

    /// Rolls back the in-memory profile state after a cancelled apply,
    /// but only when the cancelled apply still owns it (no newer apply
    /// has re-armed since). Ownership is checked via the apply token: a
    /// newer arm bumps the token, so the late-arriving cancellation of
    /// the displaced apply leaves the newer apply's state — including
    /// its in-flight flag — untouched.
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

    /// Refreshes the cached active-profile spec to match a freshly saved
    /// layout, without performing any moves. Called when the user updates the
    /// currently-active profile (Update Layout / Update All): the saved layout
    /// is captured from the live savedSectionOrder, so the bar is already in
    /// the target arrangement and only the in-memory spec that drives
    /// late-arrival re-sorts needs to catch up. armProfileState runs only on
    /// apply, so without this an update leaves activeProfileLayout pointing at
    /// the pre-update spec and the next late-arrival re-sort reverts the bar
    /// until the profile is re-applied.
    ///
    /// Unlike armProfileState this performs a pure cache refresh: it does not
    /// touch savedSectionOrder or the live pinning sets (the snapshot already
    /// equals them), does not arm isApplyingProfileLayout, and does not cancel
    /// an in-flight re-sort.
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

    /// Persists the profile's pinning sets and saved section order to
    /// disk. Called from each applyProfileLayout success exit so the
    /// on-disk intent only commits once the bar reflects it. No-op for
    /// .savedOrder (that path doesn't overwrite either store).
    private func persistProfileStateOnSuccess(source: ApplySource) {
        guard case .profile = source else { return }
        persistPinnedBundleIDs()
        persistSavedSectionOrder()
        // Committed: the pre-arm snapshot can no longer be rolled back to.
        priorProfileApplySnapshot = nil
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

    /// Cleanup for a profile apply that needed no item moves: the bar was
    /// already in the target arrangement, so the move loop is skipped and the
    /// normal Phase 7 exit (which clears the in-flight flag) is never reached.
    /// This early exit must run the same profile-only teardown as Phase 7,
    /// otherwise a no-moves apply (common on a display reconnect, where the
    /// active-display profile is re-applied onto an already-correct bar) leaks
    /// isApplyingProfileLayout = true and permanently blocks applySavedLayout
    /// for the rest of the session.
    func concludeProfileApplyWithoutMoves(source: ApplySource, items: [MenuBarItem]) {
        persistProfileStateOnSuccess(source: source)
        clearProfileState(source: source, items: items)
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
            // `appState` is now `@Observable` (wave 4); Observation tracks
            // the `imageCache` mutations above directly, so the manual
            // `objectWillChange.send()` poke is no longer needed.
        }
    }

    func applyProfileLayout(
        _ spec: ProfileLayoutSpec,
        source: ApplySource = .profile,
        automatic: Bool = false,
        duringSettling: Bool = false
    ) async {
        let pinnedHidden = spec.pinnedHidden
        let pinnedAlwaysHidden = spec.pinnedAlwaysHidden
        let rawSectionOrder = spec.sectionOrder
        let rawItemSectionMap = spec.itemSectionMap
        let rawItemOrder = spec.itemOrder
        // A profile saved before an item was renamed after its app still
        // names it by its helper (`at.obdev.littlesnitch.agent:Item-0`).
        // Migrate on the way in so the plan is built against identifiers
        // the live bar can actually produce; the profile on disk is
        // rewritten the next time the layout is persisted. Keyed maps are
        // migrated too, or the section lookup misses the renamed entry.
        let sectionOrder = LayoutSolver.canonicalizedSectionOrder(rawSectionOrder)
        let itemOrder = LayoutSolver.canonicalizedSectionOrder(rawItemOrder)
        let itemSectionMap = Dictionary(
            rawItemSectionMap.map { (LayoutSolver.canonicalIdentifier($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        // MARK: Phase 0: gate on startup settling

        //
        // During settling, cacheItemsRegardless skips restore and
        // absorbs every current item into profileSortedItemIdentifiers;
        // a layout applied here has its moves silently shadowed and the
        // late-arrival re-sort path is broken for items that appeared
        // inside the window.
        //
        // The settling-period early apply (duringSettling) is exempt: it
        // exists to run inside the window, and its caller is the cache
        // cycle that holds the serial cacheGate. Waiting here deadlocks
        // that pair — the settling task's early exit needs a cache cycle
        // the held gate rejects — so the wait always lasts the full
        // settling deadline and the item cache is frozen with unresolved
        // identities for the whole minute (#943).
        if !duringSettling {
            await waitForStartupSettlingToEnd()
        }

        // Automatic applies additionally wait for the user to stop
        // interacting. `automatic` is the same distinction
        // `automaticBulkApplyPermitted` already draws at the two dispatch
        // sites: a late-arrival re-sort or a saved-layout restore is
        // something Thaw decided to do, and it can afford to wait for a
        // lull. A profile the user just picked cannot — they are watching
        // for it to happen, and their hand is still on the mouse that
        // picked it.
        if automatic {
            // The escape hatch. Checked before the idle wait so a bar in
            // manual mode spends nothing at all on an apply it will not
            // perform, and before armProfileState so no profile state is
            // armed for a sequence that never runs.
            let automaticArrangementEnabled = (Defaults.object(forKey: .automaticArrangementEnabled) as? Bool)
                ?? Defaults.DefaultValue.automaticArrangementEnabled
            guard automaticArrangementEnabled else {
                MenuBarItemManager.diagLog.info(
                    "Profile layout: skipping automatic apply; automaticArrangementEnabled is false (manual arrangement only)"
                )
                return
            }
            // The dispatch sites check this too, but every automatic caller
            // funnels through here, so enforcing it at the funnel keeps a
            // future dispatch site from bypassing the breaker unknowingly.
            guard isAutomaticBulkApplyPermitted(caller: "Profile layout") else {
                return
            }
            await waitForBulkApplyIdleWindow()
        }

        // Bail before arming any profile state if cancellation arrived
        // during the settling wait (a newer apply has replaced us via
        // applyProfile's layoutTask?.cancel()).
        if Task.isCancelled {
            return
        }

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

        // Token identifying this apply's ownership of the armed profile
        // state. Captured immediately after arming, before any await can
        // let a newer apply re-arm. Only meaningful for the .profile
        // source (the cancellation rollback below is gated on it).
        let applyToken = profileApplyToken

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
        // Drop transient System Status Item Clone windows before planning.
        // partitionUnmanagedUIDs would otherwise classify a clone as an
        // unmanaged item and anchor it into a section, dragging a phantom
        // and reshuffling the bar. This fetch is independent of the cache
        // path, so it needs its own filter.
        items.removeAll(where: \.isSystemClone)

        // Skip the bulk apply while the majority of items have no resolved
        // sourcePID — uniqueIdentifier (used to match items against
        // itemOrder/itemSectionMap) is derived from sourcePID via
        // MenuBarItemTag's namespace, so an unresolved-PID majority means
        // the identifiers used for matching are unreliable.
        let unresolvedSourcePIDCount = items.count { $0.sourcePID == nil }
        if Self.majorityOfSourcePIDsUnresolved(unresolvedCount: unresolvedSourcePIDCount, itemCount: items.count) {
            MenuBarItemManager.diagLog.info(
                "applyProfileLayout: skipping, \(unresolvedSourcePIDCount)/\(items.count) items have unresolved sourcePIDs (XPC resolution likely failed)"
            )
            clearProfileState(source: source, items: items)
            return
        }

        // Never drag items while a menu bar item menu is tracking — a synthetic
        // Cmd-drag would tear down the user's interaction (Wi-Fi picker, input
        // methods). State is unwound so a subsequent apply can retry cleanly.
        if await isAnyMenuBarItemMenuOpen() {
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

        // The always-hidden divider is what tells always-hidden items apart
        // from hidden ones. Without it findSection collapses the two sections,
        // so Phase 1 reads every always-hidden item as sitting in hidden and
        // plans a cross-section move for each one. Those moves land — the
        // mover finds the divider by tag even when the pair could not — and
        // change nothing, so the next pass plans the same set again.
        //
        // #881's 08:41 log dragged the same six items 69 times over four
        // minutes on `ahCtrlUID=nil, crossSectionMoves=8`, the always-hidden
        // divider having gone unresolved in 552 of 578 cycles.
        //
        // `saveSectionOrder` already refuses to persist this reading (#849).
        // Refusing to move on it is the same judgement one step earlier: an
        // apply that cannot see the boundary cannot plan across it. The state
        // is unwound so the next cache tick retries once the pair resolves.
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

        // AX-frame correlation is sufficient for a read-only cache snapshot,
        // but not for any synthetic drag. Even ordinary-item LCS destinations
        // depend on section classification and may fall back to one of these
        // dividers, so restricting only direct divider moves is not enough.
        guard controlItems.canRepositionControlItems else {
            MenuBarItemManager.diagLog.warning(
                "applyProfileLayout: skipping, control items resolved only by provisional AX-frame correlation"
            )
            if case .profile = source {
                restoreProfileStateAfterAbortedApply(token: applyToken)
            }
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
        // section iteration, once via the explicit append), which desyncs
        // it from the single-divider desiredFlat and makes the LCS plan
        // spurious divider moves every cycle.
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
        // Flatten with control items at the section boundaries via the shared
        // pure helper, so this path and the log-replay harness build currentFlat
        // identically.
        var currentFlat = LayoutSolver.flattenCurrentSections(
            visible: sectionUIDs[.visible] ?? [],
            hidden: sectionUIDs[.hidden] ?? [],
            alwaysHidden: sectionUIDs[.alwaysHidden] ?? [],
            hiddenCtrlUID: hiddenCtrlUID,
            ahCtrlUID: ahCtrlUID
        )

        // Filter desired sequence to only items present in the current bar.
        let currentSet = Set(currentFlat)
        var desiredFiltered = desiredFlat.filter { currentSet.contains($0) }

        // Record which of the profile's identifiers still correspond to
        // something on the bar. This is the one place in the apply that knows
        // both halves at once, and it sits past every early return, so an
        // apply that never looked at the bar cannot be counted as evidence
        // that an item is gone. Only the profile's own entries are sampled —
        // control items are always present and would dilute the ratio the
        // ledger uses to throw out a degraded pass.
        let plannedIdentifiers = Set(itemOrder.values.joined())
        staleIdentifierLedger.recordApply(
            planned: plannedIdentifiers,
            matched: plannedIdentifiers.intersection(currentSet)
        )

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
        // Generic Control Center items (Item-N title) with no resolved source
        // PID are widgets macOS hosts under Control Center that Thaw cannot yet
        // attribute to their owning app (e.g. Little Snitch's agent before its
        // marker window appears). They fall back to the com.apple.controlcenter
        // namespace, never match a profile entry, and so would be relocated as
        // unmanaged arrivals on every cycle. Exclude them until they resolve.
        let provisionalIdentityUIDs = LayoutSolver.provisionalIdentityUIDs(items: items)
        let unmanagedUIDs = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: currentFlat,
            desiredUIDs: desiredSet,
            hiddenCtrlUID: hiddenCtrlUID,
            ahCtrlUID: ahCtrlUID,
            visibleCtrlUID: visibleCtrlUID,
            provisionalIdentityUIDs: provisionalIdentityUIDs
        )
        if !unmanagedUIDs.isEmpty {
            // Build a DesiredLayout for the profile-apply context: the
            // saved layout is the source of truth for previously-seen
            // items; NewItemsPlacement is the fallback for unseen ones.
            // Pinning is left empty here because this code path only
            // positions unmanaged items, not the profile spec items.
            // Retired identifiers are dropped before the lookup, not after:
            // the saved position is an *index* into these arrays, so a ghost
            // ahead of a live entry pushes a returning item one slot right of
            // where the user left it, every time, forever. The same pruned
            // order must feed the application below — a saved index only
            // means anything in the space it was computed in.
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

            // Per-uid decision trace. Shows which item was deemed
            // unmanaged and which placement strategy fired. Cheap
            // (only logs when unmanaged items exist) and the most
            // direct signal for triaging "why did X move?" reports.
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

        // On notched displays, calculate available visible space and overflow
        // items that won't fit into the hidden section. The Thaw visible
        // control icon stays as the last visible item (nearest the hidden divider).
        // Gated by the user-facing "Enable menu bar item overflow" toggle in
        // Advanced Settings; when off, the saved profile layout is honoured
        // verbatim and items the notch would otherwise eject stay in visible.
        // The overflow gate reads the *actual* active menu bar screen — no
        // `NSScreen.main` fallback. Guessing a screen while the active one is
        // unknown risks budgeting against the wrong display, which is the
        // exact failure this gate prevents, so the gate fails closed instead.
        let activeMenuBarScreen = NSScreen.screenWithActiveMenuBar
        let activeIsMainDisplay = activeMenuBarScreen?.displayID == CGMainDisplayID()
        // A notched display that isn't the main menu bar display only hosts the
        // status items transiently (while it holds focus); ejecting there
        // strands profile items in hidden once focus returns to the main
        // screen. Log the skips so the field logs make the reason explicit.
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

            // Replace (not union) so items freed by a previous overflow drop
            // out of the tracked set once they no longer overflow.
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
            // Overflow doesn't apply here (no notch, or the feature is off):
            // this apply restores the saved layout verbatim, so the ejection
            // bookkeeping is obsolete.
            notchOverflowEjectedUIDs.removeAll()
        }

        // Re-check the divider geometry the saved-order dispatch already
        // refused, this time against the bounds this apply actually planned
        // from. applySavedLayout tests the cache cycle's snapshot, but Phase 2
        // re-reads every item from the Window Server, so the dividers can
        // collapse in between — and it is *these* bounds that classified the
        // sections above. A collapse means findSection misread the whole
        // hidden section as .visible, so the moves below would drag it to the
        // wrong side of the dividers and, by separating them, un-trip the
        // saveSectionOrder gate so the next cycle persists the damage (#868).
        // Refusing here leaves the bar untouched; the change gate re-fires via
        // layout divergence once the geometry recovers.
        //
        // Profile applies are exempt: their hidden count is a target, not a
        // description of the current bar, so a profile that fills a
        // currently-empty hidden section legitimately runs against dividers
        // that sit adjacent because nothing is between them yet.
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
            clearProfileState(source: source, items: items)
            return
        }

        // Hide cursor for the entire profile apply to avoid visual jitter.
        // Capture in CoreGraphics space (top-left origin) so the Phase 7
        // restore can warp back directly — CGWarpMouseCursorPosition takes
        // CoreGraphics coordinates, matching what each inner move() already
        // uses. The previous AppKit capture flipped against the cursor's
        // *containing* screen instead of the primary, so on vertically
        // stacked or mixed-height multi-monitor setups the restore warped
        // the cursor onto the wrong display.
        //
        // The hide is released by `restoreCursor()` as soon as the last move
        // lands, *not* at function exit: everything after Phase 6 (control
        // item width restoration, the settling sleeps, the closing
        // getMenuBarItems pass, state persistence) moves no cursor, so
        // keeping it hidden there only lengthens the window in which the
        // user has no pointer. The `defer` is the balance for the early
        // return paths that never reach the end of Phase 6.
        let savedCursorPosition = MouseHelpers.locationCoreGraphics
        var cursorRestored = false
        func restoreCursor() {
            guard !cursorRestored else { return }
            cursorRestored = true
            // savedCursorPosition is already in CoreGraphics coordinates, so
            // warp back directly with no AppKit→CG flip (and no dependence on
            // which screen contains it).
            if let savedCursorPosition {
                MouseHelpers.restoreCursorPosition(to: savedCursorPosition)
            }
            MouseHelpers.showCursor()
        }
        MouseHelpers.hideCursor(watchdogTimeout: .seconds(30))
        defer { restoreCursor() }

        // Spans the whole move sequence below (Phase 6). Lets
        // postMoveEvents skip its own per-item hide/show — this hide
        // already covers the sequence, and Phase 7 below restores the
        // cursor once at the end.
        isBulkApplyInProgress = true
        defer { isBulkApplyInProgress = false }

        // MARK: Phase 6: LCS execution

        // ── Sub-phase 0: Move control items to optimal boundary positions ──
        //
        // Moving a control item reassigns all items on either side to
        // different sections in a single move. Calculate whether moving
        // a control item is cheaper than moving individual items.
        var movedCount = 0
        var didAttemptHCtrl = false
        /// Set when a boundary repair carried items across H_ctrl instead of
        /// carrying H_ctrl across them. Either way the sections the AH_ctrl
        /// planning below reads are stale afterwards.
        var didCrossHiddenBoundary = false
        var canRepositionControlItems = controlItems.canRepositionControlItems
        // Moves this batch planned for an item that is still on the bar and
        // then did not enact. Any of these leaves the bar in an arrangement
        // nobody asked for, which the saveSectionOrder gate must not treat
        // as an order of record (#900).
        var unenactedMoveCount = 0

        /// Every abandon exits the same way: the abandoned remainder is one
        /// more unenacted move, the outcome feeds the circuit breaker, and
        /// in-flight profile state is torn down before the deferred cache
        /// refresh reconciles against reality. Callers with their own log
        /// line pass nil.
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

        // Classify items into the two sets Phase 1 actually consults.
        // Read from the sectionByWindowID snapshot built earlier so the
        // classification here matches what the cache-log loop reported
        // above. Calling context.findSection again can return different
        // values for the same windowID if section.show()'s control-item
        // moves landed in between, which surfaces as an empty Phase 1
        // view of currently-occupied hidden / always-hidden sections.
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
        // Logged for the log-replay harness so the desired visible set is
        // captured rather than inferred from current visible minus control
        // items and unresolved orphans. Also feeds the hidden-divider
        // boundary check below; the crossSectionMoves / totalSectionMismatch
        // arithmetic that follows still only crosses hidden and
        // always-hidden.
        let desiredVisibleSet = Set(itemOrder["visible"] ?? [])

        // Check if AH_ctrl needs to move: items changing between hidden↔alwaysHidden.
        let wrongInHidden = currentHiddenSet.subtracting(desiredHiddenSet).intersection(desiredAHSet)
        let wrongInAH = currentAHSet.subtracting(desiredAHSet).intersection(desiredHiddenSet)
        var crossSectionMoves = wrongInHidden.count + wrongInAH.count

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
        var totalSectionMismatch = needsHiddenMove.count + needsAHMove.count

        // Items on the wrong side of H_ctrl. Both tallies above intersect
        // against currentHiddenSet / currentAHSet, so a bar whose hidden
        // divider has drifted past every managed item — leaving both sets
        // empty while the profile wants a full hidden section — scores
        // zero on both and falls through to the LCS. The LCS is blind to
        // it too: the dividers are stripped from its sequences, so a
        // divider-only divergence leaves current equal to desired and
        // plans no moves, and the apply reports "all items already in
        // correct positions" while the whole hidden section stays visible
        // (#879). One H_ctrl move fixes every one of them...
        let hiddenBoundaryOffenders = LayoutSolver.hiddenBoundaryOffenders(
            currentVisible: currentVisibleSet,
            currentHidden: currentHiddenSet,
            currentAlwaysHidden: currentAHSet,
            desiredVisible: desiredVisibleSet,
            desiredHidden: desiredHiddenSet,
            desiredAlwaysHidden: desiredAHSet
        )
        let hiddenBoundaryMismatch = hiddenBoundaryOffenders.count

        // ...but only when it is the divider that drifted. isProfileItem
        // admits the chevron, so the counts that decide this have to drop
        // Thaw's own items first, or a collapsed bar always looks like it
        // still has one item on the visible side and never qualifies for
        // the drag that would rescue it.
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
        MenuBarItemManager.diagLog.debug(
            "Profile layout Phase 1: liveConcealed=\(liveConcealedCount), liveVisible=\(liveVisibleCount), moveHiddenDivider=\(shouldMoveHiddenDivider)"
        )
        if hiddenBoundaryMismatch == 0 {
            parkedHiddenDividerMismatchStreak = 0
            didRecoverParkedHiddenDividerForCurrentMismatch = false
        }

        // ── Sub-phase 1: Restore the visible/hidden boundary ──
        //
        // Runs before the AH_ctrl placement so the always-hidden planning
        // below sees a divider pair that already brackets the right set of
        // items. Which way the repair runs is shouldMoveHiddenDivider's
        // call: a drag that re-sections everything it crosses when the
        // divider is what drifted, and per-item moves when it isn't.
        if hiddenBoundaryMismatch > 0, canRepositionControlItems, !Task.isCancelled {
            MenuBarItemManager.diagLog.debug(
                "Profile layout: \(hiddenBoundaryMismatch) item(s) on the wrong side of H_ctrl, moving \(shouldMoveHiddenDivider ? "H_ctrl to the boundary" : "them to H_ctrl")"
            )

            let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
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
            // CGDisplayBounds returns the Core Graphics display frame,
            // which is the coordinate space MenuBarItem.bounds and the
            // drag target points operate in. NSScreen.screens.map(\.frame)
            // is in AppKit's flipped coordinate space and can diverge for
            // mirrored or transitioning displays.
            let screenFrames = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
            if case .savedOrder = source,
               recoverParkedHiddenDividerIfNeeded(
                   hiddenBoundaryMismatch: hiddenBoundaryMismatch,
                   hiddenControlItem: freshControl.hidden,
                   screenFrames: screenFrames,
                   // Counted from the fresh read rather than the Phase 1 sets,
                   // which are keyed by identifier and would fold items that
                   // share one across displays into a single entry.
                   managedItemCount: allFreshItems.count(where: {
                       isProfileItem($0) && !$0.isControlItem
                   })
               )
            {
                // Keep the prior unfinished-batch arm intact without counting
                // the rebuild as another failed apply. That leaves the one
                // permitted retry available to verify the fresh divider.
                clearProfileState(source: source, items: allFreshItems)
                scheduleDeferredCacheRefresh()
                return
            }
            if shouldMoveHiddenDivider {
                // Exclude items parked off-screen from the anchor candidate set.
                // A parked item falls on no screen; using it as the
                // H_ctrl drag anchor makes the move fail every retry — AppKit
                // snaps the divider back to its autosave position on mouse-up,
                // one on-screen flicker per attempt for the full 8-attempt
                // budget (#881: cursor seizure and icon storm). The per-item
                // LCS pass handles repositioning parked items onto the bar.
                let liveMovableUIDs = Set(
                    allFreshItems.lazy.filter { item in
                        guard item.isMovable, isProfileItem(item) else { return false }
                        return LayoutSolver.isOnScreen(bounds: item.bounds, screenFrames: screenFrames)
                    }.map(\.uniqueIdentifier)
                )
                // Thaw's own control items clear both filters above whatever the
                // rest of the bar is doing: they are movable, and they stay on
                // screen even on a pass where every real item the profile puts on
                // this side of the divider has been dragged to the other side and
                // parked. That leaves the chevron as the anchor of last resort in
                // exactly the passes where the bar has diverged most, and dragging
                // H_ctrl up to it collapses the section the apply was restoring
                // (#958). The LCS pass below already bars them for the same
                // reason (#924, #927).
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
                            // The divider itself has to be on screen for the drag
                            // to land. #881 excluded parked *anchors*; a parked
                            // H_ctrl fails the same way from the other side — the
                            // drag point is on screen so the owner accepts the
                            // events, but AppKit still snaps the divider back to
                            // its autosave position on mouse-up, and every attempt
                            // reports "events succeeded but item not at
                            // destination" for the full budget (#899). The
                            // per-item LCS pass below repositions items without
                            // needing the divider to travel.
                            unenactedMoveCount += 1
                            MenuBarItemManager.diagLog.warning(
                                "Profile layout: H_ctrl is parked offscreen (minX=\(hItem.bounds.minX)), skipping the boundary move"
                            )
                        } else if failureLedger.isUnderBackoff(for: hItem) {
                            // Same governance the per-item moves below already get.
                            // Without it a boundary move that cannot land is retried
                            // in full by every re-sort — eight drags a pass, a pass
                            // every few seconds, for as long as the mismatch stands.
                            // In #899 that ran until the user killed the app.
                            unenactedMoveCount += 1
                            MenuBarItemManager.diagLog.warning(
                                "Profile layout: H_ctrl under move-failure backoff, skipping"
                            )
                        } else {
                            MenuBarItemManager.diagLog.debug("Profile layout: moving H_ctrl → \(dest.logString)")
                            didAttemptHCtrl = true
                            do {
                                try await move(item: hItem, to: dest, skipInputPause: true)
                                movedCount += 1
                                failureLedger.recordSuccess(for: hItem)
                                try? await Task.sleep(for: .milliseconds(200))
                            } catch {
                                unenactedMoveCount += 1
                                // A move cancelled by a newer apply says nothing
                                // about the divider, and recording it would earn
                                // H_ctrl a backoff window it did not deserve —
                                // the same rule the LCS pass applies below.
                                if Task.isCancelled {
                                    MenuBarItemManager.diagLog.debug(
                                        "Profile layout: H_ctrl move interrupted by a newer apply; leaving it unrecorded"
                                    )
                                } else {
                                    if !Self.moveAlreadyFiledFailure(for: error) {
                                        failureLedger.recordFailure(for: hItem, kind: Self.failureKind(of: error))
                                    }
                                    MenuBarItemManager.diagLog.error("Profile layout: failed to move H_ctrl: \(error)")
                                }
                            }
                        }
                    }
                } else if let refusedAnchor = LayoutSolver.hiddenDividerAnchorCandidate(
                    desiredHidden: desiredHidden,
                    desiredVisible: desiredVisible,
                    liveMovableUIDs: liveMovableUIDs
                ).flatMap({ controlItemUIDs.contains($0) ? $0 : nil }) {
                    // Separated from the case below so a soak can tell the two
                    // apart: this one means the profile's items are on the bar
                    // but on the wrong side of the divider, which is the state
                    // the LCS pass fixes and this move used to make worse.
                    MenuBarItemManager.diagLog.warning(
                        "Profile layout: only \(refusedAnchor) was left to anchor the H_ctrl boundary move; leaving the divider where it is"
                    )
                } else {
                    // No live movable member on either side to anchor against;
                    // the LCS pass below still runs against whatever ordering
                    // divergence remains.
                    MenuBarItemManager.diagLog.warning(
                        "Profile layout: no anchor available for the H_ctrl boundary move"
                    )
                }
            } else if !LayoutSolver.isOnScreen(
                bounds: freshControl.hidden.bounds,
                screenFrames: screenFrames
            ) {
                // H_ctrl is the destination for every move the branch below
                // would make, and a destination off the display gets a press
                // at a point no owner is watching. #899 is the same failure
                // seen from the divider's own side. recoverParkedHiddenDivider
                // above rebuilds the divider once the mismatch persists; until
                // then the LCS pass is the one that can make progress.
                unenactedMoveCount += 1
                MenuBarItemManager.diagLog.warning(
                    "Profile layout: H_ctrl is parked offscreen (minX=\(freshControl.hidden.bounds.minX)), skipping the per-item boundary moves"
                )
            } else {
                // The divider is roughly where it belongs and some items have
                // wandered across it. Carry those items to the divider rather
                // than the divider to them: the drag that would reach them
                // re-sections every item it passes, and on a bar this close to
                // correct that is most of the bar (#958).
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
                    // Parked or immovable. The LCS pass below is the one that
                    // brings items back onto the bar; it also crosses the
                    // boundary, just without a divider drag.
                    MenuBarItemManager.diagLog.debug(
                        "Profile layout: \(offenderUIDs.count - offenders.count) boundary offender(s) not live and movable, leaving them to the LCS pass"
                    )
                }

                // Each move lands its item immediately beside H_ctrl and
                // pushes the previous one further from it, so walking the
                // group away from the divider preserves the order they were
                // already in. Same reasoning as the notch-overflow eject.
                let toConceal = hiddenBoundaryOffenders.wronglyVisible
                    .compactMap { offenders[$0] }
                    .sorted { $0.bounds.minX < $1.bounds.minX }
                let toReveal = hiddenBoundaryOffenders.wronglyConcealed
                    .compactMap { offenders[$0] }
                    .sorted { $0.bounds.minX > $1.bounds.minX }

                for (item, dest) in toConceal.map({ ($0, MoveDestination.leftOfItem(hItem)) })
                    + toReveal.map({ ($0, MoveDestination.rightOfItem(hItem)) })
                {
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
                        try await move(item: item, to: dest, skipInputPause: true)
                        movedCount += 1
                        didCrossHiddenBoundary = true
                        failureLedger.recordSuccess(for: item)
                    } catch {
                        unenactedMoveCount += 1
                        // A move cancelled by a newer apply says nothing about
                        // the item, and recording it would earn a backoff
                        // window it did not deserve.
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
                        }
                    }
                }
            }
        }

        // A boundary repair changes the section of everything that crossed,
        // whether the divider moved or the items did. The snapshot used to
        // decide the repair is therefore stale at this point; classify the
        // post-move bounds again before deciding whether an AH_ctrl move
        // (and its per-item fallback) is still warranted.
        if didAttemptHCtrl || didCrossHiddenBoundary {
            var postMoveItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
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
            // Moving AH_ctrl to the correct position is 1 move that
            // fixes all hidden↔alwaysHidden assignments.
            MenuBarItemManager.diagLog.debug(
                "Profile layout: \(crossSectionMoves) items would change hidden↔alwaysHidden, moving AH_ctrl instead"
            )

            let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            var allFreshItemsCopy = allFreshItems
            guard let freshControl = ControlItemPair(
                items: &allFreshItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems,
            let ahItem = freshControl.alwaysHidden
            else {
                abandonApply(
                    reason: "control items degraded before moving AH_ctrl",
                    items: allFreshItems
                )
                return
            }

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
            let dest: MoveDestination? = if let firstHiddenUID = desiredHiddenUIDs.first,
                                            let firstHidden = allFreshItems.first(where: { $0.uniqueIdentifier == firstHiddenUID && $0.isMovable })
            {
                // Place AH_ctrl to the LEFT of the rightmost hidden
                // item. This puts AH_ctrl between AH items and
                // hidden items.
                .leftOfItem(firstHidden)
            } else {
                // Hidden is empty; AH_ctrl goes next to H_ctrl.
                .leftOfItem(freshControl.hidden)
            }

            if let dest, !Task.isCancelled {
                MenuBarItemManager.diagLog.debug("Profile layout: moving AH_ctrl → \(dest.logString)")
                do {
                    try await move(item: ahItem, to: dest, skipInputPause: true)
                    movedCount += 1
                    try? await Task.sleep(for: .milliseconds(200))
                } catch {
                    unenactedMoveCount += 1
                    MenuBarItemManager.diagLog.error("Profile layout: failed to move AH_ctrl: \(error)")
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
                            unenactedMoveCount += 1
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
                            unenactedMoveCount += 1
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
        if movedCount > 0 || didAttemptHCtrl {
            // Re-fetch items and rebuild section assignments after
            // the control item move changed section boundaries.
            items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            var itemsCopy2 = items
            guard let freshControl = ControlItemPair(
                items: &itemsCopy2,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems else {
                MenuBarItemManager.diagLog.error("applyProfileLayout: lost control items after phase 1")
                // Abandoning here is itself an unenacted move: the LCS pass
                // never ran, and without the dividers the sections read back
                // from the bar are not the ones this apply was producing.
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
        var desiredNoControls = desiredFiltered.filter { $0 != hiddenCtrlUID && $0 != ahCtrlUID }

        // Optionally surrender ordering inside the concealed sections. The
        // relaxation runs on the desired sequence rather than on the
        // planned moves so the LCS itself sees those items as already in
        // place: filtering moves out afterwards would leave the surviving
        // moves anchored against items the plan assumed had shifted.
        let enforceConcealedOrder = (Defaults.object(forKey: .enforceConcealedSectionOrder) as? Bool)
            ?? Defaults.DefaultValue.enforceConcealedSectionOrder
        if !enforceConcealedOrder {
            desiredNoControls = LayoutSolver.relaxConcealedSectionOrder(
                desiredNoControls: desiredNoControls,
                currentNoControls: currentNoControls,
                sectionMap: sectionMap
            )
        }

        // The hidden and always-hidden dividers were filtered out of the
        // sequences above, but the chevron stays in: its position within
        // visible is part of the layout and is persisted. That also makes it
        // selectable as a move anchor, and anchoring a failing move on one of
        // Thaw's own dividers is what walks it across the bar (#924, #927).
        // Keep it in the order, bar it from being an anchor.
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
            // A control item that refused to move counts even when the LCS
            // pass has nothing left to plan: the divider is the boundary
            // that decides which section every item is in, so the sections
            // the cache reads back are not the ones this apply intended.
            recordBulkApplyOutcome(unenactedMoveCount: unenactedMoveCount)
            concludeProfileApplyWithoutMoves(source: source, items: items)
            scheduleDeferredCacheRefresh()
            return
        }

        MenuBarItemManager.diagLog.info(
            "Profile layout: \(plannedMoves.count) item move(s) needed (\(movedCount) control move(s) preceded)"
        )

        // Failures with no success between them; feeds moveBatchShouldAbandon.
        // Backoff skips do not count — they cost nothing and say nothing new.
        var consecutiveMoveFailures = 0

        for (plannedIndex, planned) in plannedMoves.enumerated() {
            // A cancelled sequence is one a newer apply replaced, and that
            // apply owns the arrangement from here on, so its own tally is
            // the one the gate should read. Leave the remainder uncounted.
            guard !Task.isCancelled else { break }

            if failureLedger.isUnderBackoff(key: planned.uid) {
                unenactedMoveCount += 1
                MenuBarItemManager.diagLog.warning(
                    "Profile layout: \(planned.uid) under move-failure backoff, skipping"
                )
                continue
            }

            let allFreshItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            var freshItemsCopy = allFreshItems
            guard let freshControl = ControlItemPair(
                items: &freshItemsCopy,
                hiddenControlItemWindowID: hiddenWID,
                alwaysHiddenControlItemWindowID: alwaysHiddenWID
            ), freshControl.canRepositionControlItems else {
                // Losing the dividers abandons this move and every one
                // after it, so the whole remainder goes unenacted.
                unenactedMoveCount += plannedMoves.count - plannedIndex
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
                consecutiveMoveFailures = 0
                failureLedger.recordSuccess(for: item)
                try? await Task.sleep(for: .milliseconds(200))
            } catch {
                // The loop head's rule extends to a move that was in flight
                // when the cancellation arrived: the failure is the newer
                // apply's takeover, not the item's. Recording it would earn
                // an innocent item a backoff window and re-arm the save
                // withhold for a batch whose tally the newer apply owns
                // (#900's cannotComplete storms during overlapping applies).
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
                if Self.moveBatchShouldAbandon(consecutiveFailures: consecutiveMoveFailures) {
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

        // No-op on the paths that already restored at the end of Phase 6;
        // covers any branch that reaches here with the cursor still hidden.
        restoreCursor()

        // Re-fetch items after moves and update the snapshot so the
        // late-arrival detection doesn't re-trigger for items we just sorted.
        // Profile-only: the profile-sorted snapshot and
        // isApplyingProfileLayout flag are only meaningful when a
        // profile is active; the savedOrder source leaves them alone.
        items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        // A cancelled profile apply (a newer apply replaced us via
        // applyProfile's layoutTask?.cancel()) must not commit anything:
        // roll back the in-memory profile state to the last committed
        // profile so the late-arrival re-sort path doesn't keep sorting
        // toward the cancelled spec, and skip the deferred cache refresh
        // (the apply that replaced us schedules its own at exit). The
        // rollback is token-guarded: if the newer apply has already
        // re-armed the state, it is left untouched.
        if Task.isCancelled, case .profile = source {
            restoreProfileStateAfterAbortedApply(token: applyToken)
            return
        }
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
    /// section show/hide animations. Exact instance identifiers participate
    /// directly; base-identifier fallback is allowed only when all saved
    /// instances for that base belong to one section, avoiding false positives
    /// from multi-instance items split across sections.
    /// Pure decision helper (#754) for whether a rebuild of the control
    /// items' underlying status items should be triggered, given the
    /// number of consecutive `ControlItemPair` lookup failures seen so far.
    /// Extracted so the escalation threshold can be unit-tested without a
    /// live `NSStatusItem`. The episode latch resets only after a successful
    /// lookup, so a permanent failure can trigger at most one rebuild.
    static nonisolated func shouldRebuildControlItems(
        consecutiveFailures: Int,
        alreadyRebuilt: Bool = false,
        threshold: Int = MenuBarItemManager.controlItemRebuildThreshold
    ) -> Bool {
        !alreadyRebuilt && consecutiveFailures >= threshold
    }

    /// The wait a change-detector recache must respect while control-item
    /// lookups keep failing, or `nil` while no backoff applies.
    ///
    /// A lookup failure leaves the window-ID snapshot uncommitted so the
    /// change detector re-fires — which is right for a transient race and
    /// wrong for a failure that is not going away: #933's process spent 27
    /// hours running a full recache every poll against a permanently
    /// missing control item. Below the rebuild threshold there is no wait,
    /// so startup transients recover at full speed; past it the wait
    /// doubles per failure and caps, keeping recovery automatic (a retry
    /// still runs every `maxDelay`) without the constant churn. Real
    /// changes are unaffected — event-driven recaches bypass the detector.
    static nonisolated func controlItemLookupRetryBackoff(
        consecutiveFailures: Int,
        threshold: Int = MenuBarItemManager.controlItemRebuildThreshold,
        baseDelay: Duration = .seconds(6),
        maxDelay: Duration = .seconds(60)
    ) -> Duration? {
        guard consecutiveFailures >= threshold else {
            return nil
        }
        // Cap the exponent before shifting so a long-running streak cannot
        // overflow; 1 << 6 * baseDelay already exceeds every realistic cap.
        let exponent = min(consecutiveFailures - threshold, 6)
        return min(baseDelay * (1 << exponent), maxDelay)
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
    /// Both rebuild paths exist to discard a stale autosave position, and both
    /// discard it by writing the seed `preflightSetup` uses on a fresh install.
    /// That value describes a bar Thaw has never arranged. Writing it onto a
    /// bar that already holds managed items drops the rebuilt divider on one
    /// side of all of them, and the next cache pass reads the entire bar into a
    /// single section — the collapse `preflightSetup` documents for #895,
    /// reached through the same guard-bypassing write that reopened it for
    /// #890.
    ///
    /// #958's log is the direct evidence: one rebuild in five hours, and the
    /// visible section goes from 12 items to 1 within three seconds of it,
    /// while three earlier parkings that never rebuilt leave the bar intact.
    ///
    /// Skipping the stamp does not cost the recovery its purpose. Discarding
    /// the old `NSStatusItem` is what gives the divider a window on the current
    /// bar again; the follow-up apply the caller schedules is what walks it to
    /// the saved boundary.
    static nonisolated func canSeedRebuiltDividerPosition(managedItemCount: Int) -> Bool {
        managedItemCount == 0
    }

    /// The preferred position a divider rebuild should stamp, or `nil` to
    /// rebuild without touching the stored position.
    ///
    /// The value matches the one `ControlItem.preflightSetup` seeds for the
    /// hidden divider, so an empty bar still lands where a fresh install puts
    /// it.
    static nonisolated func seedPositionForRebuiltDivider(managedItemCount: Int) -> CGFloat? {
        canSeedRebuiltDividerPosition(managedItemCount: managedItemCount) ? 1 : nil
    }

    /// Log fragment naming what a divider rebuild did with the stored
    /// position, so a field log says which branch ran without the reader
    /// having to infer it from the collapse that follows.
    static nonisolated func seedDescription(_ seedPosition: CGFloat?) -> String {
        guard let seedPosition else {
            return " and keeping its stored position (the bar holds managed items)"
        }
        return " at its seeded position (\(seedPosition))"
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

    private func currentLayoutDivergesFromSaved(
        items: [MenuBarItem],
        controlItems: ControlItemPair
    ) -> Bool {
        // While the overflow feature is enabled and the active menu bar is
        // on a notched display, items the overflow rebalance ejected into
        // hidden diverge from the saved layout by design — reporting them
        // as divergent would re-dispatch a bulk apply every cache cycle.
        // The skip requires all three of: the feature still enabled (a
        // toggle-off must restore items promptly), a notched active display
        // (elsewhere the divergence is what triggers the restoring apply),
        // and the item actually sitting in hidden (an ejected item that
        // drifted to another section is genuine drift).
        let overflowSkipActive = (appState?.settings.advanced.enableMenuBarItemOverflow ?? false)
            && ((NSScreen.screenWithActiveMenuBar ?? NSScreen.main)?.hasNotch ?? false)

        return Self.layoutDivergesFromSaved(
            candidates: items
                .filter { !$0.isControlItem && $0.canBeHidden && $0.isMovable }
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

    /// Whether any item sits in a different section than `savedSectionOrder`
    /// records for it.
    ///
    /// This is the second of `applySavedLayout`'s two triggers, and the one
    /// that fires on ambient drift rather than on items coming and going. Both
    /// exemptions are passed in rather than derived so the rule stays pure:
    ///
    /// - `overflowExemptUIDs` carries the notch-overflow ejections, and is
    ///   empty unless the caller has already established that the feature is
    ///   on and the active display is notched.
    /// - `activelyShownTags` carries the items Thaw is temporarily showing. One
    ///   of those sits outside its saved section because Thaw put it there, and
    ///   it stays there until the rehide runs. Reading that as drift arms a
    ///   bulk apply whose only remaining brake is the open-menu probe, and a
    ///   false negative from the probe then drags the item home underneath the
    ///   menu the user just opened, tearing the menu down (#924). The rehide is
    ///   what returns these items; this pass has no business racing it.
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

    /// Decides whether a windowID-set difference between two cache cycles is a
    /// genuine change that should trigger a saved-layout re-apply, or merely an
    /// artifact of the active menu bar display switching to another screen.
    ///
    /// With "Displays have separate Spaces" enabled the menu bar follows the
    /// active display, so on a switch the previous display's item windows leave
    /// the active-space window list and read as "missing" even though the same
    /// logical items are still present on the other screen. Treating that as an
    /// item quit fires a full bulk re-sort on every cross-screen focus change,
    /// which on a notched display drifts items into always-hidden. A display
    /// switch is not a layout edit, so it must not advance the gate; the
    /// divergence check still runs and catches genuine section drift.
    static nonisolated func windowIDsChanged(
        previous: Set<CGWindowID>,
        current: Set<CGWindowID>,
        previousDisplayID: CGDirectDisplayID?,
        currentDisplayID: CGDirectDisplayID?
    ) -> Bool {
        // First cycle: no prior frame to diff against.
        guard !previous.isEmpty else { return false }
        // The active menu bar display moved to another screen. With separate
        // Spaces the prior display's windows are no longer on the active space,
        // so they read as missing even though the same logical items are still
        // present elsewhere. Not an item quit; do not advance the gate. Only
        // suppress when both displays are known and genuinely differ, so an
        // unknown display falls back to the plain disappearance signal.
        if let previousDisplayID, let currentDisplayID, previousDisplayID != currentDisplayID {
            return false
        }
        return !previous.isSubset(of: current)
    }

    /// Whether enough menu bar items are missing a resolved source PID that
    /// bulk-applying the saved layout would act on unmatchable identities.
    ///
    /// When the MenuBarItemService XPC connection fails (service cold start,
    /// connection interruption), most third-party items resolve to a nil
    /// sourcePID and collapse to ambiguous Control-Center-owned identifiers.
    /// A bulk apply dispatched in that state rearranges items it cannot match
    /// to the saved layout. A few system items (WiFi, Clock, BentoBox) and
    /// notch-hidden stragglers legitimately resolve to nil, so a minority
    /// share is normal; only a majority signals a resolution failure. The
    /// item-count floor keeps degenerate tiny sets from tripping the gate.
    static nonisolated func majorityOfSourcePIDsUnresolved(unresolvedCount: Int, itemCount: Int) -> Bool {
        itemCount >= 4 && unresolvedCount * 2 > itemCount
    }

    /// The profile's items that have appeared since the last profile sort,
    /// and so warrant a re-sort.
    ///
    /// Items with an unresolved `sourcePID` are excluded. `uniqueIdentifier`
    /// is derived from `sourcePID` via the tag's namespace, so an item whose
    /// PID did not resolve carries a fallback identity — it collapses into
    /// the Control Center host namespace or repeats its bundle ID as the
    /// title. Counting those as arrivals turns a resolution flap into a
    /// re-sort: the same item alternates between
    /// `eu.exelban.Stats:CPU_bar_chart` and `eu.exelban.Stats:eu.exelban.Stats:1`,
    /// and whichever form the last sort did not see reads as brand new.
    ///
    /// #881's reporter sat at 16–17 of 34 items unresolved for most of an
    /// hour — under ``majorityOfSourcePIDsUnresolved``'s bar, which needs a
    /// strict majority — so the applies ran and re-ran, each one landing its
    /// moves and each one re-arming the next.
    ///
    /// Excluding them costs nothing real: a late arrival is an app's item
    /// appearing after launch, and those resolve. The items that legitimately
    /// hold a nil PID (Wi-Fi, Clock, BentoBox) are always-present system
    /// items that never arrive late in the first place.
    static nonisolated func lateArrivingProfileIdentifiers(
        items: [MenuBarItem],
        profileIdentifiers: Set<String>,
        alreadySortedIdentifiers: Set<String>
    ) -> Set<String> {
        let identifiable = Set(
            items.lazy
                .filter { !$0.isControlItem && $0.sourcePID != nil }
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
    /// Dropping an identifier from the desired order leaves the
    /// corresponding item untouched rather than mispositioned, because
    /// ``LayoutSolver/planLCSMoveSequence(currentNoControls:desiredNoControls:sectionMap:)``
    /// intersects current with desired and only moves identifiers present in
    /// both. Section keys are preserved even when they empty out, so the
    /// caller can tell an empty section from a missing one.
    ///
    /// The match is exact rather than base-identifier: a base match could
    /// admit an unresolved sibling of a resolved item (`Item-0:1` resolved,
    /// `Item-0:2` not), which is exactly what this restriction excludes.
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
    /// A single divergent reading of `currentLayoutDivergesFromSaved` can be
    /// transient: an app activating with a wide application menu compresses
    /// or covers status items, shifting their bounds for the duration the
    /// menu is up. Reading that shift as "items in the wrong section" and
    /// immediately dispatching a bulk apply replays the whole layout and
    /// yanks the cursor around (#723) for geometry that resolves itself once
    /// the menu closes. Requiring the same divergence to be observed on two
    /// consecutive cache cycles filters out that transient case while still
    /// reacting promptly to genuine, persistent drift.
    ///
    /// - Parameters:
    ///   - divergedNow: The result of the current cycle's divergence check.
    ///   - pendingSince: The timestamp of a prior unconfirmed observation, if
    ///     one is armed.
    ///   - now: The current time.
    ///   - staleness: How long an armed observation remains eligible for
    ///     confirmation. A stale arm is discarded and treated as a fresh
    ///     first observation rather than confirmed, so an old, likely
    ///     unrelated observation can't confirm a much later one.
    /// - Returns: Whether this observation confirms the divergence (i.e.
    ///   should trigger the apply), and the pending-observation state to
    ///   carry forward to the next cycle.
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
            // First observation: arm and defer this pass.
            return (false, now)
        }
        guard now - pendingSince <= staleness else {
            // The prior arm is too old to confirm against; discard it and
            // re-arm on this observation instead.
            return (false, now)
        }
        // Second consecutive observation within the staleness window: confirmed.
        return (true, nil)
    }

    /// Whether a bulk apply that left moves unenacted should still hold
    /// the saveSectionOrder gate shut.
    ///
    /// Time alone cannot make the partial result authoritative: allowing this
    /// latch to expire rewrites the saved order with the failed batch's own
    /// wreckage on the next cache change (#900). A clean apply clears the
    /// latch through `recordBulkApplyOutcome`; an explicit user move clears it
    /// through `recordExternalMoveOperation`.
    static nonisolated func unfinishedMoveBatchBlocksSave(
        observedAt: ContinuousClock.Instant?
    ) -> Bool {
        observedAt != nil
    }

    /// Whether an automatic apply may dispatch given how the recent ones
    /// ended.
    ///
    /// A batch that fails is allowed one retry: the failure can be
    /// circumstantial (a menu was up, an owner was mid-relaunch) and the
    /// retry is what the save-withhold window exists to make room for. A
    /// second consecutive unfinished batch means the bar itself is
    /// refusing the moves (#900's `cannotComplete` bar), and each further
    /// pass costs the user a hidden cursor for the length of the batch
    /// while landing yet another partial arrangement (#899). From then on
    /// dispatch is rationed to one attempt per cooldown rather than one
    /// per confirmed divergence, which is unbounded when the divergence
    /// is the failed batches' own.
    ///
    /// User-initiated applies (a profile switch) do not consult this gate:
    /// an explicit request is worth a fresh attempt regardless of history.
    /// They still feed the streak through `recordBulkApplyOutcome`, so a
    /// failed manual attempt does not hand the automatic path a clean
    /// slate.
    static nonisolated func automaticBulkApplyPermitted(
        consecutiveUnfinishedBatches: Int,
        lastUnfinishedBatchAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        maxConsecutive: Int = 2,
        cooldown: Duration = .seconds(60),
        hardCap: Int = 6
    ) -> Bool {
        if consecutiveUnfinishedBatches < maxConsecutive {
            return true
        }
        if consecutiveUnfinishedBatches >= hardCap {
            return false
        }
        guard let lastUnfinishedBatchAt else {
            return true
        }
        return now - lastUnfinishedBatchAt >= cooldown
    }

    /// Whether a move batch should abandon its remaining moves after a run
    /// of consecutive failures.
    ///
    /// The cursor stays hidden for the whole batch, and a failing move is
    /// the expensive kind: it burns its full attempt budget, each attempt
    /// with an event timeout and a settle wait, before throwing. On the
    /// #900 bar one pass logged 15 such failures — minutes of a dead
    /// pointer (#899) spent confirming the same conclusion. Three in a row
    /// with no success between them is that conclusion: the bar is
    /// refusing synthetic drags right now, and the items still queued will
    /// fare no better. The abandoned remainder counts as unenacted, so the
    /// arrangement is withheld from the saved order like any other partial
    /// batch.
    ///
    /// Consecutive, not total: successes reset the run, so a long batch
    /// with scattered failures — each already filed with the ledger for
    /// per-item backoff — still completes.
    static nonisolated func moveBatchShouldAbandon(
        consecutiveFailures: Int,
        threshold: Int = 3
    ) -> Bool {
        consecutiveFailures >= threshold
    }

    /// The idle window an automatic bulk apply should wait for, or `nil`
    /// when the gate is switched off.
    ///
    /// Splitting the sanitising out of the wait loop keeps the two things
    /// that can be got wrong — "is the gate on" and "when does waiting
    /// stop" — testable without a clock. A non-positive threshold is the
    /// off switch rather than a zero-length window, so the caller can skip
    /// the loop entirely; a negative cap is clamped rather than rejected,
    /// because a `defaults write` typo should degrade to "don't wait", not
    /// to a batch that never starts.
    static nonisolated func bulkApplyIdleWindow(
        thresholdMs: Int,
        capMs: Int
    ) -> (threshold: Duration, cap: Duration)? {
        guard thresholdMs > 0 else { return nil }
        return (.milliseconds(thresholdMs), .milliseconds(max(0, capMs)))
    }

    /// Whether an automatic bulk apply has waited long enough to start
    /// issuing moves.
    ///
    /// Two exits, and the second is the important one: the wait defers a
    /// batch, it never cancels it. A user who never stops moving the mouse
    /// would otherwise starve the apply indefinitely, and a saved layout
    /// that is never restored is a worse failure than one restored while
    /// the pointer is in motion — the per-move pause still applies once the
    /// batch is under way.
    static nonisolated func bulkApplyIdleWaitConcluded(
        userHasPausedInput: Bool,
        elapsed: Duration,
        cap: Duration
    ) -> Bool {
        userHasPausedInput || elapsed >= cap
    }

    /// The previous cache cycle's state that ``applySavedLayout`` diffs
    /// the current bar against to decide whether a restore is warranted.
    nonisolated struct PreviousCacheCycle {
        var windowIDs: [CGWindowID]
        var displayID: CGDirectDisplayID?
        var ccGenericWindowIDs: Set<CGWindowID> = []
    }

    func applySavedLayout(
        items: [MenuBarItem],
        previousCycle: PreviousCacheCycle,
        controlItems: ControlItemPair,
        currentDisplayID: CGDirectDisplayID? = nil,
        bypassMoveCooldown: Bool = false,
        resolvedIdentitiesOnly: Bool = false
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
        // applyProfileLayout owns the in-flight layout while it's
        // running; a concurrent savedOrder apply would fight it.
        guard !isApplyingProfileLayout else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, profile apply in flight")
            return false
        }
        // 5 s cooldown after a recent move (same value the legacy
        // restoreItemsToSavedSections used) prevents cascading
        // re-applies when many apps relaunch in quick succession.
        //
        // bypassMoveCooldown opts the launch restore out: that pass runs
        // immediately after relocateNewLeftmostItems has moved our own
        // control item, so the cooldown it would observe is one this same
        // chain just stamped. There is no later retry, so honouring the
        // cooldown here means the saved layout is never applied at all and
        // the drifted arrangement gets persisted over it (#881).
        guard bypassMoveCooldown || !lastMoveOperationOccurred(within: .seconds(5)) else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, within 5s move cooldown")
            return false
        }
        // Not bypassable: bypassMoveCooldown exempts a caller from a
        // cooldown its own chain just stamped, whereas this gate reads a
        // history of applies that did not complete. A launch restore is
        // unaffected anyway — the streak is session state and starts at 0.
        guard isAutomaticBulkApplyPermitted(caller: "applySavedLayout") else {
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
        //
        // A single divergent reading is required to be *stable* across two
        // consecutive cache cycles before it advances the gate (#723): an
        // app activating with a wide application menu can transiently
        // compress or cover status items, which currentLayoutDivergesFromSaved
        // reads as items in the wrong section even though the geometry
        // reverts once the menu closes. windowIDsChanged is a direct,
        // trustworthy signal (an item genuinely disappeared) and is not
        // subject to this confirmation — it stays immediate and never
        // arms/consumes the pending-divergence state below.
        let currentWindowIDSet = Set(items.map(\.windowID))
        let previousWindowIDSet = Set(previousCycle.windowIDs)
        // Control-Center-generic (`Item-N`) windows churn windowIDs while
        // the visible item count stays stable (Live Activities, transient
        // CC widgets). Their disappearance is not an app quit/relaunch and
        // must not dispatch a bulk apply, or every churn cycle replays the
        // whole layout and hijacks the cursor (#736). Their identities are
        // never part of a saved layout (saveSectionOrder excludes them), so
        // ignoring them here can't miss a restorable change.
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
        // A windowID-change apply proceeds regardless of any pending
        // divergence arm; discard the stale arm so it can't spuriously
        // confirm on a later, unrelated cycle once the bar has settled.
        pendingDivergenceObservedAt = nil

        // Skip the bulk apply while the majority of items have no resolved
        // sourcePID — mirrors relocateNewLeftmostItems's unresolved-sourcePID
        // noop.
        //
        // resolvedIdentitiesOnly callers are exempt: they deliberately run
        // while most sourcePIDs are still unresolved, and confine the apply
        // to the identities that *are* resolved (see effectiveSavedOrder).
        let unresolvedSourcePIDCount = items.count { $0.sourcePID == nil }
        if !resolvedIdentitiesOnly,
           Self.majorityOfSourcePIDsUnresolved(unresolvedCount: unresolvedSourcePIDCount, itemCount: items.count)
        {
            MenuBarItemManager.diagLog.info(
                "applySavedLayout: skipping, \(unresolvedSourcePIDCount)/\(items.count) items have unresolved sourcePIDs (XPC resolution likely failed)"
            )
            return false
        }

        // Never drag items while a menu bar item menu is tracking — a synthetic
        // Cmd-drag would tear down the user's interaction (Wi-Fi picker, input
        // methods). The change gate stays armed, so the next cache cycle retries.
        if await isAnyMenuBarItemMenuOpen() {
            MenuBarItemManager.diagLog.info("applySavedLayout: skipping, a menu bar item menu is open")
            return false
        }

        // Saved-item intersection: skip if none of the saved items are
        // currently present. Prefer exact namespace/title/instance matches;
        // fall back to namespace/title only when every saved instance for that
        // base belongs to one section. This avoids treating ambiguous
        // multi-instance Control Center items (for example Item-0:1 visible,
        // Item-0:2 hidden) as evidence that the saved layout is present and
        // needs a bulk apply.
        let sectionLookup = Self.savedLayoutSectionLookup(savedSectionOrder: savedSectionOrder)
        let currentIdentifiers = Set(items.map(\.uniqueIdentifier))
        let currentBaseIdentifiers = Set(items.map { Self.baseIdentifier(forSavedIdentifier: $0.uniqueIdentifier) })
        guard !Set(sectionLookup.exact.keys).isDisjoint(with: currentIdentifiers)
            || !Set(sectionLookup.unambiguousBase.keys).isDisjoint(with: currentBaseIdentifiers)
        else {
            MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, no saved items currently present")
            return false
        }

        // The desired order this apply will actually enact.
        //
        // Under resolvedIdentitiesOnly the saved order is narrowed to
        // identifiers whose live item has a resolved sourcePID, so an item
        // we cannot yet identify is never a move target. That is safe
        // because planLCSMoveSequence intersects current with desired and
        // only moves identifiers present in both — dropping one from
        // desired leaves it untouched rather than mispositioned. The
        // settling-end pass then runs unrestricted and, because LCS keeps
        // whatever is already in place, moves only the remainder.
        //
        // Match is exact on uniqueIdentifier: base-identifier fallback
        // could admit an unresolved sibling of a resolved item, which is
        // precisely the item this restriction exists to exclude.
        let effectiveSavedOrder: [String: [String]]
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

        // Build itemSectionMap from the effective order. Each identifier
        // points back at its persisted section key.
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

        // The apply must refuse the same geometry the save path refuses to
        // persist. When the dividers have collapsed onto one coordinate,
        // findSection has already misread every hidden item, so the section
        // mismatch computed below is an artifact of the collapse, not drift
        // to correct — dispatching here drags the whole hidden section to
        // the wrong side of the dividers with synthetic mouse events. Worse,
        // the drags separate the dividers, so the saveSectionOrder gate that
        // caught the collapse a cycle earlier passes on the next cycle and
        // persists the damage (#868). Refusing keeps the bar untouched; the
        // change gate re-fires via layout divergence once the geometry
        // recovers, and the apply then runs against a trustworthy reading.
        let hiddenSectionHasRoom = LayoutSolver.hiddenSectionHasRoom(
            hiddenControlItemMinX: controlItems.hidden.bounds.minX,
            alwaysHiddenControlItemMaxX: controlItems.alwaysHidden?.bounds.maxX,
            savedHiddenItemCount: effectiveSavedOrder[sectionKey(for: .hidden)]?.count ?? 0,
            // Read off the bar this apply was handed, not the cache: this path
            // is entered with `items` and runs before any recache.
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
            return false
        }

        // Display-spread gate. While the active menu bar relocates to another
        // display macOS migrates the status item windows between screens
        // asynchronously, so the items transiently straddle two displays. A
        // bulk apply dispatched now resolves each item's move against whichever
        // display its window currently occupies and cannot converge, stranding
        // items on the wrong screen where they read as un-hidden. Skip; a later
        // tick retries once the items collapse back onto the active display.
        // Frames come from CGDisplayBounds so they share the top-left origin
        // coordinate space of the item bounds.
        //
        // Only items right of the hidden divider feed the gate. Parked hidden
        // and always-hidden items sit at arbitrary negative x, which belongs to
        // a display positioned left of the main one, and including them reports
        // a spread on a settled layout for as long as that display is
        // connected. This gate and the saveSectionOrder one are a pair: both
        // must judge the same geometry, or the layout gets applied from an
        // order that can no longer be saved.
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

        // The shared body uses itemOrder as the per-section ordered
        // identifier list, which is structurally identical to
        // savedSectionOrder. Pass the saved order through unchanged.
        // Pinning is preserved from existing state, not derived from
        // savedSectionOrder (savedSectionOrder has no pinning concept).
        // resolvedIdentitiesOnly is set by exactly one caller: the early
        // restricted apply inside the settling branch of the cache cycle.
        // Passing it through as duringSettling exempts that apply from
        // Phase 0's settling wait, which its gate-holding caller cannot
        // survive (#943).
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
            duringSettling: resolvedIdentitiesOnly
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
            let bounds = item.liveBounds
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
        ), controlItems.canRepositionControlItems else {
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
