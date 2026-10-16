//
//  MenuBarItemManager+CachePass.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - Cache Pass

extension MenuBarItemManager {
    /// Whether bundleID owns a tracked item. The trailing ":" stops prefix
    /// matches (org.x.fdm6 vs org.x.fdm6x:Item-0).
    static nonisolated func tracksMenuBarItem(bundleID: String, in identifiers: Set<String>) -> Bool {
        identifiers.contains { $0.hasPrefix(bundleID + ":") }
    }

    /// Degraded means a generic Item-N title or a reverse-DNS, bundle-ID-shaped one.
    private static func isDegradedIdentity(_ item: MenuBarItem) -> Bool {
        if item.tag.isControlCenterGenericItem {
            return true
        }
        guard let title = item.title else { return false }
        return title.split(separator: ".").count >= 3
    }

    /// Fills degradedItemAXIdentities from an AX snapshot of Control Center and
    /// SystemUIServer, at most once per pass. Display-only.
    private func enrichDegradedItemIdentities(in items: [MenuBarItem]) {
        let degradedItems = items.filter(Self.isDegradedIdentity)
        guard !degradedItems.isEmpty else {
            degradedItemAXIdentities = [:]
            return
        }

        let hostBundleIDs = ["com.apple.controlcenter", "com.apple.systemuiserver"]
        let hosts = hostBundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        guard !hosts.isEmpty else {
            MenuBarItemManager.diagLog.debug(
                "enrichDegradedItemIdentities: \(degradedItems.count) degraded item(s) present but no Control Center/SystemUIServer host is running"
            )
            degradedItemAXIdentities = [:]
            return
        }

        let snapshot = AXIdentityCatalog.snapshot(hosts: hosts)
        var enrichment = [CGWindowID: AXIdentityCatalog.AXItemIdentity]()
        for item in degradedItems {
            let bounds = item.liveBounds
            guard let identity = AXIdentityCatalog.identity(for: bounds, in: snapshot) else { continue }
            enrichment[item.windowID] = identity
        }

        MenuBarItemManager.diagLog.debug(
            "enrichDegradedItemIdentities: \(degradedItems.count) degraded item(s), \(enrichment.count) resolved via AX-frame correlation"
        )
        degradedItemAXIdentities = enrichment
    }

    /// Records this enumeration's windowIDs and returns the set that counts as
    /// recently seen.
    ///
    /// - Parameter items: The items enumerated this cycle, after clones and
    ///   ghost control windows have been dropped.
    ///
    /// - Returns: Every windowID enumerated within the last
    ///   recentWindowIDCycleWindow cycles, including this one.
    private func recordRecentItemWindowIDs(_ items: [MenuBarItem]) -> Set<CGWindowID> {
        recentItemWindowIDCycles.append(Set(items.lazy.map(\.windowID)))
        while recentItemWindowIDCycles.count > MenuBarItemManager.recentWindowIDCycleWindow {
            recentItemWindowIDCycles.removeFirst()
        }
        return recentItemWindowIDCycles.reduce(into: Set()) { $0.formUnion($1) }
    }

    /// Flags that shape one cache pass. Every field defaults to a plain pass.
    struct CacheOptions {
        var skipRecentMoveCheck = false
        var resolveSourcePID = true
        var reuseCachedIdentities = false
        var skipSavedLayoutApply = false
        var suppressAutomaticMoves = false
        var suppressSavedOrderPersistence = false
        var bypassSavedLayoutCooldown = false
        var forcePersistSavedOrder = false
    }

    /// Caches the current items unconditionally, fixing the control item order first.
    func cacheItemsRegardless(
        _ currentItemWindowIDs: [CGWindowID]? = nil,
        options: CacheOptions = CacheOptions(),
        waiterToken: Int? = nil,
        cacheAttempt: CacheAttempt? = nil
    ) async {
        let skipRecentMoveCheck = options.skipRecentMoveCheck
        let resolveSourcePID = options.resolveSourcePID
        let reuseCachedIdentities = options.reuseCachedIdentities
        let skipSavedLayoutApply = options.skipSavedLayoutApply
        let suppressAutomaticMoves = options.suppressAutomaticMoves
        let suppressSavedOrderPersistence = options.suppressSavedOrderPersistence
        let bypassSavedLayoutCooldown = options.bypassSavedLayoutCooldown
        let forcePersistSavedOrder = options.forcePersistSavedOrder
        MenuBarItemManager.diagLog.debug(
            "cacheItemsRegardless: entering (skipRecentMoveCheck=\(skipRecentMoveCheck), hasCurrentItemWindowIDs=\(currentItemWindowIDs != nil), resolveSourcePID=\(resolveSourcePID), reuseCachedIdentities=\(reuseCachedIdentities), skipSavedLayoutApply=\(skipSavedLayoutApply), suppressAutomaticMoves=\(suppressAutomaticMoves), suppressSavedOrderPersistence=\(suppressSavedOrderPersistence), bypassSavedLayoutCooldown=\(bypassSavedLayoutCooldown), forcePersistSavedOrder=\(forcePersistSavedOrder))"
        )

        guard skipRecentMoveCheck || !lastMoveOperationOccurred(within: .seconds(1)) else {
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache due to recent item movement")
            return
        }

        guard !(appState?.isDraggingMenuBarItem ?? false) else {
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache: user is cmd-dragging")
            return
        }

        // Drop concurrent calls, or one may snapshot pre-move positions.
        guard await cacheGate.begin() else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: serial cache operation already in progress, skipping")
            return
        }
        defer { Task { await cacheGate.end() } }

        // After the gate, so a dropped call can't claim an earlier cycle's success.
        let completedCyclesAtGateEntry = completedCacheCycles
        let moveTimestampAtGateEntry = lastMoveOperationTimestamp
        func snapshotIsCurrent(_ stage: String) -> Bool {
            guard lastMoveOperationTimestamp == moveTimestampAtGateEntry else {
                MenuBarItemManager.diagLog.debug(
                    "cacheItemsRegardless: discarding stale snapshot at \(stage) because an item moved during this pass"
                )
                return false
            }
            return true
        }
        defer {
            cacheAttempt?.recordCompletion(
                cyclesAtEntry: completedCyclesAtGateEntry,
                cyclesAtExit: completedCacheCycles,
                snapshotRemainedCurrent: lastMoveOperationTimestamp == moveTimestampAtGateEntry
            )
        }

        // Relocation hand-offs pass the waiter to a nested recache. The defer
        // releases it on every other exit so it's never stranded.
        var ownsWaiter = true
        defer {
            if ownsWaiter, let waiterToken {
                resumeBackgroundCacheWaiter(waiterToken)
            }
        }

        let previousWindowIDs = cacheActor.cachedItemWindowIDs
        let previousCCGenericWindowIDs = cacheActor.cachedControlCenterGenericWindowIDs
        let displayID = Bridging.getActiveMenuBarDisplayID()
        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: displayID=\(displayID.map { "\($0)" } ?? "nil"), previousWindowIDs count=\(previousWindowIDs.count)")

        var enumeration = await MenuBarItem.getMenuBarItemsSnapshot(
            option: .activeSpace,
            resolveSourcePID: resolveSourcePID
        )
        var items = enumeration.items

        if items.isEmpty {
            // Transient WindowServer glitches and display changes can return nothing.
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: getMenuBarItems returned ZERO items, retrying in 250ms...")
            try? await Task.sleep(for: .milliseconds(250))
            enumeration = await MenuBarItem.getMenuBarItemsSnapshot(
                option: .activeSpace,
                resolveSourcePID: resolveSourcePID
            )
            items = enumeration.items

            // The bar doesn't empty itself; this is the .activeSpace filter using a
            // stale space ID. Keep the last good cache, or the layout editor blanks (#851).
            if items.isEmpty, !itemCache.managedItems.isEmpty {
                MenuBarItemManager.diagLog.warning(
                    "cacheItemsRegardless: getMenuBarItems returned ZERO items twice, keeping last-known-good cache of \(itemCache.managedItems.count) item(s)"
                )
                return
            }
        }

        // The editor only needs geometry; reusing confirmed identities skips the
        // slow AX source-PID scan without turning icons into placeholders.
        if reuseCachedIdentities {
            items = Self.reusingCachedIdentities(
                in: items,
                from: itemCache.managedItems
            )
        }

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: getMenuBarItems returned \(items.count) items")

        // WindowServer spawns clone windows during capture and animations, with
        // fresh IDs and no source PID. Drop them early so they never trip a re-layout.
        let cloneWindowIDs = Set(items.filter(\.isSystemClone).map(\.windowID))
        if !cloneWindowIDs.isEmpty {
            let cloneDescriptions = items.filter(\.isSystemClone).map(\.tag.description)
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: dropping \(cloneWindowIDs.count) system clone window(s): \(cloneDescriptions)")
            items.removeAll(where: \.isSystemClone)
        }

        // A duplicate or crashed Thaw can leave control-item titles on foreign windows.
        var ghostWindowIDs = dropGhostControlItemWindows(from: &items)

        // Drop orphans before the degradation check, which would read one as the
        // whole bar losing its names (#1032).
        ghostWindowIDs.formUnion(dropOrphanedOwnNamespaceWindows(from: &items))

        // Items titled after their owners identify nothing; caching them rewrites
        // the bar under IDs no later reading matches (#881). Keep the last good cache.
        if !itemCache.managedItems.isEmpty,
           LayoutSolver.liveIdentitiesAreDegraded(items.map { ($0.tag.namespace.description, $0.tag.title) })
        {
            MenuBarItemManager.diagLog.warning(
                "cacheItemsRegardless: reading titles items after their own owners (\(items.count) item(s)); keeping last-known-good cache of \(itemCache.managedItems.count) item(s)"
            )
            return
        }

        // Enumeration is slow; if a move landed meanwhile, discard this reading entirely.
        guard snapshotIsCurrent("after item enumeration") else { return }

        // After dropping clones and ghosts, so their throwaway IDs stay out.
        let recentWindowIDs = recordRecentItemWindowIDs(items)

        // SourcePIDCache matches CG windows to AX children spatially, which goes
        // wrong when AX lags after a move. A PID from a stable cycle is more trustworthy.
        var provisionalSourcePIDSeeds = enumeration.appliedSourcePIDSeeds
        var didReconcileSourcePID = false
        if resolveSourcePID {
            let previousBaselines = cacheActor.cachedSourcePIDBaselines
            var attemptedPIDs = Set<pid_t>()
            var identities = [pid_t: SourceProcessIdentity]()

            func cachedLiveIdentity(for pid: pid_t) -> SourceProcessIdentity? {
                if let cached = identities[pid] {
                    return cached
                }
                guard attemptedPIDs.insert(pid).inserted,
                      let resolved = SourcePIDSeedStore.liveIdentity(of: pid)
                else { return nil }
                identities[pid] = resolved
                return resolved
            }

            for i in items.indices {
                let item = items[i]
                guard
                    !item.isControlItem,
                    let previous = previousBaselines[item.windowID],
                    item.sourcePID != previous.pid,
                    let window = enumeration.windowsByID[item.windowID],
                    let controlCenterGeneration = enumeration.controlCenterGeneration,
                    SourcePIDSeedStore.reconciledSourcePID(
                        currentPID: item.sourcePID,
                        previous: previous,
                        for: window,
                        currentControlCenterGeneration: controlCenterGeneration,
                        liveIdentity: cachedLiveIdentity(for:)
                    ) == previous.pid
                else { continue }

                if let currentPID = item.sourcePID {
                    MenuBarItemManager.diagLog.warning(
                        "SourcePID changed for windowID \(item.windowID): \(previous.pid) -> \(currentPID), reverting to the generation-validated baseline"
                    )
                } else {
                    MenuBarItemManager.diagLog.info(
                        "SourcePID unresolved for windowID \(item.windowID); restoring the generation-validated in-session baseline \(previous.pid)"
                    )
                    provisionalSourcePIDSeeds[item.windowID] = previous
                }

                let correctedNamespace = MenuBarItemTag.Namespace.optional(
                    previous.bundleIdentifier ?? previous.processName
                )
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
                    sourcePID: previous.pid,
                    bounds: item.bounds,
                    title: item.title,
                    isOnScreen: item.isOnScreen
                )
                didReconcileSourcePID = true
            }
        }

        // Reconciling can change a namespace but keep the instanceIndex, so two
        // items can collide. Regroup the indices.
        if didReconcileSourcePID {
            MenuBarItem.assignStableInstanceIndices(to: &items, using: enumeration.windowsByID)
        }

        // A newly resolved identifier would look new to relocateNewLeftmostItems.
        // Skip unresolved sourcePIDs so the placeholder namespace is never persisted.
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

        // The raw window list may still hold clone or ghost IDs.
        let itemWindowIDs = (currentItemWindowIDs ?? items.reversed().map(\.windowID))
            .filter { !cloneWindowIDs.contains($0) && !ghostWindowIDs.contains($0) }
        // Don't commit the window IDs yet: if the ControlItemPair guard fails, the
        // change detector would stop firing right when recovery depends on it.

        await MainActor.run {
            MenuBarItemTag.Namespace.pruneUUIDCache(keeping: Set(itemWindowIDs))
            self.pruneMoveOperationTimeouts(keeping: Set(items.map(\.tag)))
            self.pruneClickOperationTimeouts(keeping: Set(items.map(\.tag)))
        }
        guard snapshotIsCurrent("after cache pruning") else { return }

        // Lets ControlItemPair match by window ID when tag and title fail (macOS 26+).
        let hiddenControlItemWindowNumber = appState?.menuBarManager
            .controlItem(withName: .hidden)?.window?.windowNumber
        let alwaysHiddenControlItemWindowNumber = appState?.menuBarManager
            .controlItem(withName: .alwaysHidden)?.window?.windowNumber
        let hiddenControlItemWID = hiddenControlItemWindowNumber.flatMap {
            Self.authoritativeControlItemWindowID(windowNumber: $0)
        }
        let alwaysHiddenControlItemWID = alwaysHiddenControlItemWindowNumber.flatMap {
            Self.authoritativeControlItemWindowID(windowNumber: $0)
        }
        let observedControlCenterGeneration = Self.controlCenterGeneration()

        guard let controlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenControlItemWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWID
        ) else {
            guard snapshotIsCurrent("before control-item recovery") else { return }
            // Keep the last good cache and leave the window IDs uncommitted so the
            // detector re-fires (#754). After controlItemRebuildThreshold failures in a
            // row the status items themselves are gone, so rebuild them.
            if !suppressAutomaticMoves,
               Self.resetControlItemLookupEpisodeIfHostChanged(
                   previous: lastObservedControlCenterGeneration,
                   current: observedControlCenterGeneration,
                   failureStreak: &controlItemLookupFailureStreak,
                   alreadyRebuilt: &didRebuildControlItemsForCurrentFailureEpisode
               )
            {
                lastControlItemLookupFailureAt = nil
                lastObservedControlCenterGeneration = observedControlCenterGeneration
            }
            let hostUptime = Self.controlCenterUptime(
                generation: observedControlCenterGeneration
            )
            guard Self.shouldCountControlItemLookupFailure(
                hostUptime: hostUptime,
                suppressAutomaticMoves: suppressAutomaticMoves
            ) else {
                MenuBarItemManager.diagLog.info(
                    suppressAutomaticMoves
                        ? "cacheItemsRegardless: Missing control item during Layout-editor refresh; not advancing recovery or scheduling an automatic recache. Items remaining: \(items.count)"
                        : "cacheItemsRegardless: Missing control item for hidden section \(hostUptime.map { "\(Int($0.milliseconds / 1000)) s" } ?? "?") after Control Center launched; not counting it toward a rebuild while the bar is being re-hosted. Items remaining: \(items.count)"
                )
                await MainActor.run {
                    self.areControlItemsMissing = true
                }
                return
            }
            controlItemLookupFailureStreak += 1
            lastControlItemLookupFailureAt = .now
            let failureStreak = controlItemLookupFailureStreak
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: Missing control item for hidden section (expected tag: \(MenuBarItemTag.hiddenControlItem)), keeping last-known-good cache. Items remaining: \(items.count), windowIDs: \(itemWindowIDs.count). hiddenWindowNumber=\(hiddenControlItemWindowNumber.map(String.init) ?? "nil"), hiddenControlItemWID=\(hiddenControlItemWID.map(String.init) ?? "nil"), alwaysHiddenWindowNumber=\(alwaysHiddenControlItemWindowNumber.map(String.init) ?? "nil"), alwaysHiddenControlItemWID=\(alwaysHiddenControlItemWID.map(String.init) ?? "nil"). consecutiveFailures=\(failureStreak)")
            await MainActor.run {
                self.areControlItemsMissing = true
            }

            if MenuBarItemManager.shouldRebuildControlItems(
                consecutiveFailures: failureStreak,
                alreadyRebuilt: didRebuildControlItemsForCurrentFailureEpisode
            ) {
                MenuBarItemManager.diagLog.warning("cacheItemsRegardless: \(failureStreak) consecutive control item lookup failures, rebuilding hidden/always-hidden status items")
                await MainActor.run {
                    appState?.menuBarManager.controlItem(withName: .hidden)?.recreateStatusItem()
                    appState?.menuBarManager.controlItem(withName: .alwaysHidden)?.recreateStatusItem()
                }
                didRebuildControlItemsForCurrentFailureEpisode = true
                // Recache now. The short wait lets this cycle's cacheGate.end() run,
                // or the recache is dropped, and lets the new windows register.
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    await self?.cacheItemsRegardless()
                }
            }
            return
        }

        if controlItems.canRepositionControlItems {
            controlItemLookupFailureStreak = 0
            didRebuildControlItemsForCurrentFailureEpisode = false
            lastControlItemLookupFailureAt = nil
            if let observedControlCenterGeneration {
                lastObservedControlCenterGeneration = observedControlCenterGeneration
            }
            cacheActor.updateCachedItemWindowIDs(itemWindowIDs)
            cacheActor.updateCachedCloneWindowIDs(cloneWindowIDs.union(ghostWindowIDs))
            cacheActor.updateCachedControlCenterGenericWindowIDs(
                Set(items.filter(\.tag.isControlCenterGenericItem).map(\.windowID))
            )
        }

        await MainActor.run {
            self.areControlItemsMissing = false
        }
        guard snapshotIsCurrent("after control-item discovery") else { return }

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: found control items, hidden windowID=\(controlItems.hidden.windowID), alwaysHidden=\(controlItems.alwaysHidden.map { "\($0.windowID)" } ?? "nil")")

        // A display change can strand the always-hidden divider on another screen
        // while the pair still succeeds, so the rebuild above never fires (#863).
        // Only authoritative cycles count; a disabled section's divider is absent on purpose.
        if !suppressAutomaticMoves, controlItems.canRepositionControlItems {
            if appState?.settings.advanced.enableAlwaysHiddenSection == true {
                if controlItems.alwaysHidden == nil {
                    missingAlwaysHiddenDividerStreak += 1
                    if Self.shouldRecoverMissingAlwaysHiddenDivider(
                        consecutiveMissingReadings: missingAlwaysHiddenDividerStreak,
                        alreadyRecovered: didRecoverMissingAlwaysHiddenDivider
                    ) {
                        didRecoverMissingAlwaysHiddenDivider = true
                        MenuBarItemManager.diagLog.warning(
                            "cacheItemsRegardless: always-hidden section enabled but its divider has not resolved for \(missingAlwaysHiddenDividerStreak) consecutive cycles, recreating it"
                        )
                        await MainActor.run {
                            appState?.menuBarManager.controlItem(withName: .alwaysHidden)?.recreateStatusItem()
                        }
                        Task { [weak self] in
                            try? await Task.sleep(for: .milliseconds(100))
                            await self?.cacheItemsRegardless()
                        }
                    }
                } else {
                    missingAlwaysHiddenDividerStreak = 0
                    didRecoverMissingAlwaysHiddenDivider = false
                }
            } else {
                missingAlwaysHiddenDividerStreak = 0
                didRecoverMissingAlwaysHiddenDivider = false
            }
        }

        if Self.isDegradedIdentityEnrichmentEnabled {
            enrichDegradedItemIdentities(in: items)
        } else if !degradedItemAXIdentities.isEmpty {
            degradedItemAXIdentities = [:]
        }

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled after control item discovery")
            return
        }

        guard snapshotIsCurrent("before control-item order enforcement") else { return }
        if !suppressAutomaticMoves {
            let controlItemOrderOutcome = await enforceControlItemOrder(
                controlItems: controlItems,
                shouldBeginMove: {
                    snapshotIsCurrent("control-item order move preflight")
                }
            )
            if controlItemOrderOutcome.needsAuthoritativeRecache {
                MenuBarItemManager.diagLog.debug(
                    "Control-item reorder attempt reached moveGate; scheduling authoritative recache"
                )
                // Position-only changes keep window IDs, so the detector can't see them.
                ownsWaiter = false
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsRegardless(
                        options: .init(
                            skipRecentMoveCheck: true,
                            resolveSourcePID: resolveSourcePID,
                            reuseCachedIdentities: reuseCachedIdentities,
                            skipSavedLayoutApply: skipSavedLayoutApply
                                || controlItemOrderOutcome.shouldSuppressAutomaticMovesDuringRecache,
                            suppressAutomaticMoves: suppressAutomaticMoves
                                || controlItemOrderOutcome.shouldSuppressAutomaticMovesDuringRecache,
                            suppressSavedOrderPersistence: suppressSavedOrderPersistence
                                || controlItemOrderOutcome.shouldSuppressSavedOrderPersistenceDuringRecache,
                            bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                            forcePersistSavedOrder: forcePersistSavedOrder
                        ),
                        waiterToken: waiterToken
                    )
                }
                return
            }
        }

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled before relocateNewLeftmostItems")
            return
        }
        guard snapshotIsCurrent("after control-item order enforcement") else { return }

        // A relaunched app keeps its identifier but gets a new windowID and lands
        // wherever macOS puts it. Drop it from the sorted snapshot so the
        // late-arrival path picks it up. Must run before the early returns below,
        // whose recache records the new windowID and loses the signal.
        //
        // Idle wake and AX rebinding also recreate status items in place, so only
        // drop items in the wrong section. Undeterminable sections still drop.
        if !suppressAutomaticMoves,
           let activeLayout = activeProfileLayout,
           !activeProfileItemIdentifiers.isEmpty,
           !previousWindowIDs.isEmpty
        {
            let previousWindowIDSet = Set(previousWindowIDs)
            let hiddenMinX = controlItems.hidden.bounds.minX
            let hiddenMaxX = controlItems.hidden.bounds.maxX
            let ahBounds = controlItems.alwaysHidden?.bounds

            var expectedSectionByID = [String: String]()
            for (sectionKey, ids) in activeLayout.itemOrder {
                for id in ids {
                    expectedSectionByID[id] = sectionKey
                }
            }

            /// Mirrors currentLayoutDivergesFromSaved. Items straddling a divider
            /// return nil to avoid false positives during show/hide animations.
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

        if !suppressAutomaticMoves {
            let newLeftmostOutcome = await relocateNewLeftmostItems(
                items,
                controlItems: controlItems,
                previousWindowIDs: previousWindowIDs,
                recentWindowIDs: recentWindowIDs,
                shouldBeginMove: {
                    snapshotIsCurrent("new-item relocation move preflight")
                }
            )
            if newLeftmostOutcome.needsAuthoritativeRecache {
                MenuBarItemManager.diagLog.debug(
                    "New-leftmost relocation attempt reached moveGate; scheduling authoritative recache"
                )
                // Ownership transfers to the nested recache: the waiter must not
                // be told the cache is settled until the second cycle finishes.
                ownsWaiter = false
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    // The launch restore runs in this recache. After a failed accepted
                    // attempt, movers are suppressed so it can't retry-loop.
                    await self?.cacheItemsRegardless(
                        options: .init(
                            skipRecentMoveCheck: true,
                            resolveSourcePID: resolveSourcePID,
                            reuseCachedIdentities: reuseCachedIdentities,
                            skipSavedLayoutApply: skipSavedLayoutApply
                                || newLeftmostOutcome.shouldSuppressAutomaticMovesDuringRecache,
                            suppressAutomaticMoves: suppressAutomaticMoves
                                || newLeftmostOutcome.shouldSuppressAutomaticMovesDuringRecache,
                            suppressSavedOrderPersistence: suppressSavedOrderPersistence
                                || newLeftmostOutcome.shouldSuppressSavedOrderPersistenceDuringRecache,
                            bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                            forcePersistSavedOrder: forcePersistSavedOrder
                        ),
                        waiterToken: waiterToken
                    )
                }
                return
            }
        }
        guard snapshotIsCurrent("after new-item relocation check") else { return }

        if !suppressAutomaticMoves {
            let pendingRelocationOutcome = await relocatePendingItems(
                items,
                controlItems: controlItems,
                shouldBeginMove: {
                    snapshotIsCurrent("pending-item relocation move preflight")
                }
            )
            if pendingRelocationOutcome.needsAuthoritativeRecache {
                MenuBarItemManager.diagLog.debug(
                    "Pending-item relocation attempt reached moveGate; scheduling authoritative recache"
                )
                // Ownership transfers to the nested recache: the waiter must not
                // be told the cache is settled until the second cycle finishes.
                ownsWaiter = false
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsRegardless(
                        options: .init(
                            skipRecentMoveCheck: true,
                            resolveSourcePID: resolveSourcePID,
                            reuseCachedIdentities: reuseCachedIdentities,
                            skipSavedLayoutApply: skipSavedLayoutApply
                                || pendingRelocationOutcome.shouldSuppressAutomaticMovesDuringRecache,
                            suppressAutomaticMoves: suppressAutomaticMoves
                                || pendingRelocationOutcome.shouldSuppressAutomaticMovesDuringRecache,
                            suppressSavedOrderPersistence: suppressSavedOrderPersistence
                                || pendingRelocationOutcome.shouldSuppressSavedOrderPersistenceDuringRecache,
                            bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                            forcePersistSavedOrder: forcePersistSavedOrder
                        ),
                        waiterToken: waiterToken
                    )
                }
                return
            }
        }
        guard snapshotIsCurrent("after pending-item relocation check") else { return }

        // Settling prevents cascading moves while many apps load at login;
        // a final pass afterwards restores.
        guard !isInStartupSettling else {
            await uncheckedCacheItems(
                items: items,
                controlItems: controlItems,
                displayID: displayID,
                suppressAutomaticMoves: suppressAutomaticMoves,
                suppressSavedOrderPersistence: suppressSavedOrderPersistence,
                forcePersistSavedOrder: forcePersistSavedOrder,
                snapshotIsCurrent: { snapshotIsCurrent("startup cache publish") }
            )
            guard snapshotIsCurrent("after startup cache publish") else { return }
            // So items appearing during settling aren't late arrivals afterwards.
            if !suppressAutomaticMoves, activeProfileLayout != nil {
                for item in items where !item.isControlItem {
                    profileSortedItemIdentifiers.insert(item.uniqueIdentifier)
                }
            }

            // One early apply for already-identified items, instead of showing
            // macOS's arrangement for all of settling (~8 s, #881).
            // Bypasses the cooldown: relocateThawIcon stamps it within ~100 ms of
            // launch, and this runs only once per settling period.
            if !skipSavedLayoutApply,
               !suppressAutomaticMoves,
               lastMoveOperationTimestamp == moveTimestampAtGateEntry,
               !didAttemptEarlySavedLayoutApply
            {
                let didApply = await applySavedLayout(
                    items: items,
                    previousCycle: PreviousCacheCycle(
                        windowIDs: previousWindowIDs,
                        displayID: itemCache.displayID,
                        ccGenericWindowIDs: previousCCGenericWindowIDs
                    ),
                    controlItems: controlItems,
                    currentDisplayID: displayID,
                    bypassMoveCooldown: true,
                    resolvedIdentitiesOnly: true,
                    shouldBegin: {
                        snapshotIsCurrent("early saved-layout apply preflight")
                    }
                )
                // Only a real dispatch spends the one attempt.
                if didApply {
                    didAttemptEarlySavedLayoutApply = true
                    MenuBarItemManager.diagLog.debug(
                        "cacheItemsRegardless: early saved-layout apply dispatched during settling"
                    )
                    return
                }
            } else if !skipSavedLayoutApply,
                      lastMoveOperationTimestamp != moveTimestampAtGateEntry
            {
                MenuBarItemManager.diagLog.debug(
                    "cacheItemsRegardless: skipping early saved-layout apply because an item moved during this cache pass"
                )
            }

            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: startup settling active, skipping restore")
            return
        }

        // Restore the saved layout when window IDs change (app relaunch).
        //
        // skipSavedLayoutApply keeps the post-apply refresh from re-entering here.
        // Control Center widgets churn windowIDs, so otherwise it loops forever.
        if !skipSavedLayoutApply,
           !suppressAutomaticMoves,
           lastMoveOperationTimestamp == moveTimestampAtGateEntry
        {
            let didApplySavedLayout = await applySavedLayout(
                items: items,
                previousCycle: PreviousCacheCycle(
                    windowIDs: previousWindowIDs,
                    displayID: itemCache.displayID,
                    ccGenericWindowIDs: previousCCGenericWindowIDs
                ),
                controlItems: controlItems,
                currentDisplayID: displayID,
                bypassMoveCooldown: bypassSavedLayoutCooldown,
                shouldBegin: {
                    snapshotIsCurrent("saved-layout apply preflight")
                }
            )
            if didApplySavedLayout {
                return
            }
        } else if !skipSavedLayoutApply,
                  lastMoveOperationTimestamp != moveTimestampAtGateEntry
        {
            MenuBarItemManager.diagLog.debug(
                "cacheItemsRegardless: skipping saved-layout apply because an item moved during this cache pass"
            )
        }

        guard snapshotIsCurrent("before cache publish") else { return }
        await uncheckedCacheItems(
            items: items,
            controlItems: controlItems,
            displayID: displayID,
            suppressAutomaticMoves: suppressAutomaticMoves,
            suppressSavedOrderPersistence: suppressSavedOrderPersistence,
            forcePersistSavedOrder: forcePersistSavedOrder,
            snapshotIsCurrent: { snapshotIsCurrent("cache publish") }
        )
        guard snapshotIsCurrent("after cache publish") else { return }

        // The settle-end fast restore resolves nothing and must not overwrite the baseline.
        if resolveSourcePID {
            let currentWindowIDs = Set(items.map(\.windowID))
            let currentControlCenterGeneration = SourcePIDSeedStore.currentControlCenterGeneration()
            let validatedProvisionalSeeds: [CGWindowID: SourcePIDSeed]
            let freshSeeds: [SourcePIDSeed]

            if let currentControlCenterGeneration {
                var attemptedPIDs = Set<pid_t>()
                var identities = [pid_t: SourceProcessIdentity]()

                func cachedLiveIdentity(for pid: pid_t) -> SourceProcessIdentity? {
                    if let cached = identities[pid] {
                        return cached
                    }
                    guard attemptedPIDs.insert(pid).inserted,
                          let resolved = SourcePIDSeedStore.liveIdentity(of: pid)
                    else { return nil }
                    identities[pid] = resolved
                    return resolved
                }

                validatedProvisionalSeeds = provisionalSourcePIDSeeds.filter { windowID, seed in
                    guard
                        currentWindowIDs.contains(windowID),
                        let window = enumeration.windowsByID[windowID]
                    else { return false }
                    return SourcePIDSeedStore.isTrustworthy(
                        seed,
                        for: window,
                        currentControlCenterGeneration: currentControlCenterGeneration,
                        liveIdentity: cachedLiveIdentity(for:)
                    )
                }
                freshSeeds = SourcePIDSeedStore.seeds(
                    from: items,
                    excluding: Set(validatedProvisionalSeeds.keys),
                    windowsByID: enumeration.windowsByID,
                    currentControlCenterGeneration: currentControlCenterGeneration,
                    identity: SourcePIDSeedStore.liveIdentity(of:)
                )
            } else {
                validatedProvisionalSeeds = [:]
                freshSeeds = []
            }

            let baselines = SourcePIDSeedStore.mergedConfirmedBaselines(
                previous: cacheActor.cachedSourcePIDBaselines,
                fresh: freshSeeds,
                provisional: validatedProvisionalSeeds
            )
            cacheActor.updateCachedSourcePIDBaselines(baselines)

            let previousPersistedSeeds = cacheActor.persistedSourcePIDSeeds(
                from: Defaults.store
            )
            let persistedSeeds = SourcePIDSeedStore.coalescingCaptureTimes(
                proposed: SourcePIDSeedStore.mergedPersistedSeeds(
                    fresh: freshSeeds,
                    provisional: validatedProvisionalSeeds
                ),
                previous: Dictionary(
                    previousPersistedSeeds.map { ($0.windowID, $0) },
                    uniquingKeysWith: { _, last in last }
                )
            )
            if cacheActor.updatePersistedSourcePIDSeeds(persistedSeeds) {
                SourcePIDSeedStore.save(persistedSeeds, to: Defaults.store)
            }

            if !validatedProvisionalSeeds.isEmpty {
                MenuBarItemManager.diagLog.debug(
                    "cacheItemsRegardless: retained \(validatedProvisionalSeeds.count) restored source PID(s) provisionally while persisting \(freshSeeds.count) fresh confirmation(s)"
                )
            }
        }

        if !suppressAutomaticMoves,
           activeProfileLayout != nil,
           !activeProfileItemIdentifiers.isEmpty
        {
            await MainActor.run {
                guard profileResortTask == nil,
                      !isApplyingProfileLayout
                else { return }
                let newProfileItems = Self.lateArrivingProfileIdentifiers(
                    items: items,
                    profileIdentifiers: activeProfileItemIdentifiers,
                    alreadySortedIdentifiers: profileSortedItemIdentifiers
                )
                if !newProfileItems.isEmpty {
                    let unidentifiable = items.count { !$0.isControlItem && $0.sourcePID == nil }
                    if unidentifiable > 0 {
                        MenuBarItemManager.diagLog.debug(
                            "Profile re-sort: ignoring \(unidentifiable) item(s) with an unresolved sourcePID when detecting arrivals"
                        )
                    }
                    MenuBarItemManager.diagLog.info("Profile re-sort: detected \(newProfileItems.count) late-arriving profile item(s): \(newProfileItems.sorted())")
                    scheduleProfileResort()
                }
            }
        }

        await MainActor.run {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: finished, cache now has \(self.itemCache.managedItems.count) managed items")
        }

        // Runs last so it sees the settled cache.
        guard snapshotIsCurrent("before notch-overflow rebalance") else { return }
        if !suppressAutomaticMoves {
            let notchRebalanceOutcome = await rebalanceNotchOverflowIfNeeded(
                items: items,
                controlItems: controlItems,
                shouldBeginMove: {
                    snapshotIsCurrent("notch-overflow move preflight")
                }
            )
            if notchRebalanceOutcome.needsAuthoritativeRecache {
                MenuBarItemManager.diagLog.debug(
                    "Notch-overflow rebalance attempted item moves; scheduling authoritative recache"
                )
                // Position moves keep window IDs, so hand the waiter to a fresh cycle.
                ownsWaiter = false
                Task { [weak self] in
                    try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
                    await self?.cacheItemsRegardless(
                        options: .init(
                            skipRecentMoveCheck: true,
                            resolveSourcePID: resolveSourcePID,
                            reuseCachedIdentities: reuseCachedIdentities,
                            skipSavedLayoutApply: skipSavedLayoutApply
                                || notchRebalanceOutcome.shouldSuppressAutomaticMovesDuringRecache,
                            suppressAutomaticMoves: suppressAutomaticMoves
                                || notchRebalanceOutcome.shouldSuppressAutomaticMovesDuringRecache,
                            suppressSavedOrderPersistence: suppressSavedOrderPersistence
                                || notchRebalanceOutcome.shouldSuppressSavedOrderPersistenceDuringRecache,
                            bypassSavedLayoutCooldown: bypassSavedLayoutCooldown,
                            forcePersistSavedOrder: forcePersistSavedOrder
                        ),
                        waiterToken: waiterToken
                    )
                }
            }
        }
    }

    /// Returns a fresh-geometry reading with previously confirmed identities
    /// restored for windows that are demonstrably the same live status item.
    static nonisolated func reusingCachedIdentities(
        in freshItems: [MenuBarItem],
        from cachedItems: [MenuBarItem]
    ) -> [MenuBarItem] {
        let cachedByWindowID = Dictionary(
            cachedItems.lazy.map { ($0.windowID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return freshItems.map { freshItem in
            guard freshItem.sourcePID == nil,
                  let cachedItem = cachedByWindowID[freshItem.windowID],
                  let cachedSourcePID = cachedItem.sourcePID,
                  cachedItem.ownerPID == freshItem.ownerPID,
                  cachedItem.title == freshItem.title
            else {
                return freshItem
            }

            return MenuBarItem(
                tag: cachedItem.tag,
                windowID: freshItem.windowID,
                ownerPID: freshItem.ownerPID,
                sourcePID: cachedSourcePID,
                bounds: freshItem.bounds,
                title: freshItem.title,
                isOnScreen: freshItem.isOnScreen
            )
        }
    }
}
