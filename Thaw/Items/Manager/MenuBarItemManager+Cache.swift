//
//  MenuBarItemManager+Cache.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit
import ThawLayout

// MARK: - Item Cache

extension MenuBarItemManager {
    /// Cross-pass comparison baselines grouped for atomic reset and synchronized window-ID collections.
    /// Only this file advances them; the rest of the app may read them.
    final class CacheCycleState {
        /// Window identifiers of the managed items as the previous pass
        /// enumerated them, already flipped out of Window Server order.
        fileprivate(set) var cachedItemWindowIDs = [CGWindowID]()

        /// Previous resolved source PIDs correct transient errors from stale AX data after moves.
        fileprivate(set) var cachedItemPIDs = [CGWindowID: pid_t]()

        /// Filter these transient clone IDs from change comparisons so clone churn does not trigger recaching.
        fileprivate(set) var cachedCloneWindowIDs = Set<CGWindowID>()

        /// Ordered owner/title identities for macOS 27, where synthetic AX window IDs churn without movement.
        /// Stable identities prevent a recache loop while detecting real additions, removals, and reorders.
        fileprivate(set) var cachedItemSignature = [String]()
    }

    /// Defined in MenuBarModel so backends can use section buckets without linking the orchestrator.
    typealias ItemCache = MenuBarModel.MenuBarItemCache

    /// The Thaw dividers pulled out of an enumeration, which the sections are
    /// measured against. Defined alongside ItemCache in MenuBarModel.
    typealias ControlItemPair = MenuBarModel.ControlItemPair

    /// Scratch state for a single pass: the dividers it measures against, the
    /// cache it is filling in, and the items it has to come back to at the end.
    struct CacheContext {
        /// The dividers this pass measures sections against.
        let controlItems: ControlItemPair

        /// The cache being filled in, published only if it differs from the
        /// one already on the manager.
        var cache: ItemCache

        init(controlItems: ControlItemPair, displayID: CGDirectDisplayID?) {
            self.controlItems = controlItems
            self.cache = ItemCache(displayID: displayID)
        }

        /// Keep the visible divider for layout drawing and section measurements.
        /// Exclude other dividers, policy exclusions, and clones before section assignment or movement.
        func isValidForCaching(_ item: MenuBarItem) -> Bool {
            if item.tag == .visibleControlItem {
                return true
            }
            if !item.sectionManagementPolicy.isVisibleInLayout {
                return false
            }
            if item.isSystemClone || item.isNativeOverflowControl {
                return false
            }
            if item.isControlItem, item.tag != .visibleControlItem {
                return false
            }
            return true
        }
    }

    /// Purge terminated owners from every section immediately so the layout editor need not wait for a debounced walk.
    /// Preserve saved section order to restore placement on relaunch.
    func purgeItemsOwnedBy(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        var removed: [String] = []
        for section in MenuBarSectionName.allCases {
            let remaining = itemCache[section].filter { item in
                let owned = item.ownerPID == pid
                if owned {
                    removed.append(item.uniqueIdentifier)
                }
                return !owned
            }
            itemCache[section] = remaining
        }
        guard !removed.isEmpty else { return }
        MenuBarItemManager.diagLog.info(
            "purgeItemsOwnedBy: removed \(removed.count) item(s) of terminated app \(app.bundleIdentifier ?? "unnamed") (pid \(pid))"
        )
    }

    /// Purge before the periodic window-list gate: macOS 27 can omit terminate notifications, and AX-only items own no window.
    /// Read LaunchServices-backed owner properties off MainActor and reject the snapshot if the cache changes during the read.
    func purgeDepartedOwners(
        readOwners: @Sendable () async -> RunningApplicationSnapshot = { await RunningApplicationSnapshot.current() }
    ) async {
        guard !isPurgingDepartedOwners, !Task.isCancelled else { return }
        isPurgingDepartedOwners = true
        defer { isPurgingDepartedOwners = false }
        let cacheAtStart = itemCache
        let owners = await readOwners()
        guard !Task.isCancelled, itemCache == cacheAtStart else { return }
        purgeDepartedOwners(
            processIDs: owners.processIDs,
            bundleIdentifiers: owners.bundleIdentifiers
        )
    }

    /// The injectable core of purgeDepartedOwners(): the live call site
    /// supplies the current process table, tests supply a fixture one.
    func purgeDepartedOwners(processIDs: Set<pid_t>, bundleIdentifiers: Set<String>) {
        let filtered = itemCache.retainingRunningOwners(
            processIDs: processIDs,
            bundleIdentifiers: bundleIdentifiers
        )
        guard filtered != itemCache else { return }
        let before = itemCache.managedItems.count
        itemCache = filtered
        MenuBarItemManager.diagLog.info(
            "purgeDepartedOwners: dropped \(before - filtered.managedItems.count) item(s) whose owner is no longer running"
        )
    }

    /// Callers must settle dividers; this path does not recheck order or recurse into repair.
    /// Retry garbled mid-reflow scans against the trailing-anchor invariant twice, then publish to avoid stalling the cache.
    private func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?,
        publicationGeneration: UInt64,
        observationOnly: Bool = false
    ) async {
        guard layoutPublication.canPublish(generation: publicationGeneration) else {
            scheduleCoalescedCacheRerun()
            return
        }
        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: processing \(items.count) items for caching")
        var items = items
        var sanityAttempts = 0
        var context = bucketedCacheContext(
            items: items,
            controlItems: controlItems,
            displayID: displayID
        )

        // One-shot, after items have settled so identifier shapes are final:
        // see pruneSavedSectionOrderGhosts() for what is safe to prune.
        if !observationOnly, !didPruneSavedSectionOrderGhosts {
            didPruneSavedSectionOrderGhosts = true
            pruneSavedSectionOrderGhosts()
        }

        while true {
            // Verify before the unchanged-cache guard: nonexistent icons recovered from the position store can produce a stable cache.
            if !observationOnly, let displayID {
                PositionStoreItemSource.verifyRecoveriesIfNeeded(
                    displayID: displayID,
                    live: items,
                    restrictionApplied: appState?.menuBarManager.sectionController.isRestrictionApplied ?? false
                )
            }

            guard itemCache != context.cache else {
                MenuBarItemManager.diagLog.debug("Menu bar item cache unchanged; leaving the published cache alone")
                return
            }

            // Validate only changed caches to catch garbled reflow scans without retrying stable violations forever.
            if !observationOnly, !isScanSanityCheckSuspended,
               let violation = scanSanityViolation(for: context.cache, on: displayID)
            {
                let maximumSanityAttempts = 2
                if sanityAttempts < maximumSanityAttempts, !Task.isCancelled {
                    let snapshot = await MenuBarItemAXProvider.menuBarInventoryConcurrent(freshOnly: true)
                    guard snapshot.hasFreshKnownInventory,
                          layoutPublication.canPublish(generation: publicationGeneration)
                    else {
                        scheduleCoalescedCacheRerun()
                        return
                    }
                    let rescan = snapshot.freshItems
                    if rescan.isEmpty {
                        MenuBarItemManager.diagLog.warning(
                            "Scan sanity re-scan returned no items; publishing the failing scan rather than an empty one"
                        )
                    } else {
                        sanityAttempts += 1
                        MenuBarItemManager.diagLog.warning(
                            "Scan sanity check failed (attempt \(sanityAttempts)/\(maximumSanityAttempts)): \(violation); re-scanning before publishing"
                        )
                        items = rescan
                        context = bucketedCacheContext(
                            items: items,
                            controlItems: controlItems,
                            displayID: displayID
                        )
                        continue
                    }
                } else {
                    MenuBarItemManager.diagLog.warning(
                        "Scan sanity check still failing after \(sanityAttempts) attempts (\(violation)); publishing latest scan"
                    )
                }
            }

            // A sanity re-scan above can suspend while an owner exits. Check
            // again at publication so the old in-flight pass cannot undo purge.
            guard layoutPublication.canPublish(generation: publicationGeneration) else {
                scheduleCoalescedCacheRerun()
                return
            }
            context.cache = context.cache.retainingRunningOwners()
            if let displayID {
                recordVisibleControlObservation(items: items, displayID: displayID)
            }
            itemCache = context.cache
            followRenamedThawBarOnlyItems()
            keepThawBarOnlyItemsHidden()
            break
        }

        guard !observationOnly else { return }

        // Reset isRestoringItemOrder if it's been stuck for too long (10 seconds).
        // This prevents stale flags from blocking saves after user manual moves.
        if isRestoringItemOrder, let timestamp = isRestoringItemOrderTimestamp, Date().timeIntervalSince(timestamp) > 10 {
            MenuBarItemManager.diagLog.debug("Resetting stale isRestoringItemOrder flag (timeout)")
            isRestoringItemOrder = false
            isRestoringItemOrderTimestamp = nil
        }

        mirrorSavedSectionOrderIfSettled(from: context.cache)
        noteUnseenMenuBarHosts(in: context.cache)

        MenuBarItemManager.diagLog.debug("Updated menu bar item cache: visible=\(context.cache[.visible].count), hidden=\(context.cache[.hidden].count), alwaysHidden=\(context.cache[.alwaysHidden].count)")

        // Rebalance external item floods here; coalesce tasks so assertion reflow cannot trigger rebalance thrashing.
        if configuration.enableMenuBarItemOverflow == true {
            scheduleOverflowRebalance(reason: .externalChange)
        }
    }

    /// Suspend trailing-anchor checks during moves and command-drags, when reflow violations are expected.
    private var isScanSanityCheckSuspended: Bool {
        lastMoveOperationOccurred(within: .seconds(1)) ||
            (appState?.isDraggingMenuBarItem ?? false)
    }

    /// Returns a trailing-anchor violation, or nil for a coherent bar.
    /// Evaluate only the active display; interleaved multi-display ordering is meaningless.
    private func scanSanityViolation(
        for cache: ItemCache,
        on displayID: CGDirectDisplayID?
    ) -> String? {
        guard let displayID else { return nil }
        let displayBounds = CGDisplayBounds(displayID)
        let onScreen = cache.managedItems.filter {
            $0.isOnScreen && $0.bounds.width > 0 && displayBounds.intersects($0.bounds)
        }
        return Self.anchoredTrailingViolation(in: MenuBarItem.sortByLeadingEdge(onScreen))
    }

    /// Reject reversed Control Center/Clock ranks or non-anchors right of the trailing group; normalization repairs stable Siri stranding.
    /// Skip Thaw controls and sub-phantomFramePeerMinimumWidth slivers (including the intentionally zero-width icon); ranks also cover legacy spellings.
    static nonisolated func anchoredTrailingViolation(
        in sortedLeftToRight: [MenuBarItem]
    ) -> String? {
        var lastAnchoredRank = Int.min
        var sawAnchored = false
        for item in sortedLeftToRight {
            guard !item.isControlItem,
                  item.bounds.width >= MenuBarItemGeometry.phantomFramePeerMinimumWidth
            else {
                continue
            }
            let rank = MenuBarItemTag.anchoredSystemItemRank(item.tag)
            if rank < 3 {
                sawAnchored = true
                guard rank >= lastAnchoredRank else {
                    return "anchored items out of canonical order at \(item.logString)"
                }
                lastAnchoredRank = rank
            } else if sawAnchored {
                return "non-anchored \(item.logString) sits right of the anchored trailing group"
            }
        }
        return nil
    }

    /// Bucket without publishing so sanity retries reuse classification without reentering the cache pass.
    private func bucketedCacheContext(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?
    ) -> CacheContext {
        var context = CacheContext(controlItems: controlItems, displayID: displayID)

        var validCount = 0
        var invalidCount = 0

        // Dedupe transient move duplicates by uniqueIdentifier; macOS 27 synthetic window IDs churn even within a pass.
        // First occurrence wins, the rightmost item in reversed Window Server order.
        var seenIdentifiers = Set<String>()

        for item in items where context.isValidForCaching(item) {
            guard seenIdentifiers.insert(item.uniqueIdentifier).inserted else {
                MenuBarItemManager.diagLog.debug("uncheckedCacheItems: skipping duplicate tag \(item.logString)")
                continue
            }

            validCount += 1
            if item.sourcePID == nil {
                MenuBarItemManager.diagLog.warning("Missing sourcePID for \(item.logString)")
            }

            // macOS 27 dividers stay collapsed; classify live geometry as visible and rebucket by RuntimeSectionController assignments.
            context.cache[.visible].append(item)
        }

        for item in items where !context.isValidForCaching(item) {
            invalidCount += 1
        }

        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: \(validCount) valid, \(invalidCount) invalid (filtered)")

        context.cache = MenuBarBackendProvider.current.rebucket(
            context.cache,
            hider: appState?.menuBarManager.sectionController,
            allowsAlwaysHidden: configuration.isAlwaysHiddenSectionEnabled
        )
        // Conceal snapshots survive exits; filter after rebucketing to avoid resurrecting departed items in both UIs.
        // Preserve assignments for relaunch placement.
        context.cache = context.cache.retainingRunningOwners()

        return context
    }

    /// The recorded Visible order to keep after an arrival shuffled the items already there, or nil.
    /// Offered only when a cursor-free write can put it back; otherwise the bar wins.
    private func visibleOrderPreservedAcrossArrival(
        mirrored: [String: [String]],
        cache: ItemCache
    ) -> [String]? {
        let liveVisible = Set(cache[.visible].map(\.uniqueIdentifier))
        let previousLiveVisible = lastMirroredLiveVisibleIdentifiers
        lastMirroredLiveVisibleIdentifiers = liveVisible
        guard !authoredVisibleOrderPendingPhysicalApply,
              !arrangementIsManual,
              !menuBarAgentIgnoresPreferredPositions,
              let previousLiveVisible
        else { return nil }
        let visibleKey = sectionKey(for: .visible)
        return Self.visibleOrderPreservedAcrossArrival(
            savedOrder: savedSectionOrder[visibleKey] ?? [],
            mirroredOrder: mirrored[visibleKey] ?? [],
            previousLive: previousLiveVisible,
            currentLive: liveVisible
        )
    }

    /// Mirror only settled, concealed geometry; reveal interleaving must not become saved order that reconciliation enforces.
    func mirrorSavedSectionOrderIfSettled(
        from cache: ItemCache,
        displays: [CGRect] = activeDisplayBounds()
    ) {
        let isAnySectionRevealed = appState?.menuBarManager.sectionController.revealedSection != nil
        let shouldPersistLayoutSnapshot = !suppressSpatialOrderPersistenceAfterFailedApply
            && !isNotificationCenterLayoutSuspended
            && !isAnySectionRevealed
            && LayoutSolver.shouldPersistSavedOrder(
                isRestoringItemOrder: isRestoringItemOrder,
                isResettingLayout: isResettingLayout,
                isInStartupSettling: isInStartupSettling,
                isApplyingProfileLayout: isApplyingProfileLayout
            )
        guard shouldPersistLayoutSnapshot else {
            return
        }
        // Concealed buckets retain old frames, which cannot describe the current bar.
        guard !Self.framesSpanSeveralBars(cache[.visible], displays: displays) else {
            MenuBarItemManager.diagLog.debug("Not mirroring section order: item frames span more than one bar")
            return
        }

        // Consolidate split groups before mirroring them back into savedSectionOrder.
        // Persistence guards ensure no move is in flight; healthy records incur no write or refresh.
        appState?.menuBarManager.sectionController.repairGroupInvariantIfNeeded()

        // Mirror RuntimeSectionController membership and cached order to keep profiles, defaults, and layout bars synchronized.
        // Preserve pending authored Visible edits over old geometry; otherwise mirror command-drags the controller cannot observe (hidden sections have no live geometry).
        let mirrored = computeSectionOrder(from: cache)
        let visibleKey = sectionKey(for: .visible)
        let preservedVisible = visibleOrderPreservedAcrossArrival(mirrored: mirrored, cache: cache)
        let resolvedMirrored: [String: [String]] = if authoredVisibleOrderPendingPhysicalApply {
            mirrored.merging(
                [MenuBarSection.Name.visible.rawValue: savedSectionOrder[visibleKey] ?? []],
                uniquingKeysWith: { _, authored in authored }
            )
        } else if let preservedVisible {
            mirrored.merging([visibleKey: preservedVisible], uniquingKeysWith: { _, preserved in preserved })
        } else {
            mirrored
        }
        defer {
            if preservedVisible != nil {
                scheduleArrivalOrderRestore()
            }
        }
        guard resolvedMirrored != savedSectionOrder else {
            return
        }
        savedSectionOrder = resolvedMirrored
        persistSavedSectionOrder()
        MenuBarItemManager.diagLog.debug(
            "Mirrored macOS 27 section order: \(resolvedMirrored.mapValues(\.count))"
        )
    }

    /// Coalesce environment and cache rebalances to prevent assertion-reflow feedback.
    /// Run the merged request so later observations cannot weaken explicit or immediate intent.
    func scheduleOverflowRebalance(
        reason: LayoutChangeReason,
        immediate: Bool = false
    ) {
        let request = OverflowRebalanceRequest(reason: reason, immediate: immediate)
        overflowRebalancePendingRequest = request.merged(into: overflowRebalancePendingRequest)
        overflowRebalanceTask?.cancel()
        overflowRebalanceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let effective = self.overflowRebalancePendingRequest ?? request
            let didRebalance = await self.rebalanceOverflowIfNeeded(
                reason: effective.reason,
                immediate: effective.immediate
            )
            // Cancelled tasks leave merged intent for their replacements.
            guard !Task.isCancelled else { return }
            self.overflowRebalancePendingRequest = nil
            if didRebalance {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await self.cacheItemsRegardless(skipRecentMoveCheck: true)
            }
        }
    }

    /// Pure merge policy for timing-independent tests: explicit reasons win and immediacy is sticky.
    nonisolated struct OverflowRebalanceRequest: Equatable, Sendable {
        var reason: LayoutChangeReason
        var immediate: Bool

        func merged(into pending: OverflowRebalanceRequest?) -> OverflowRebalanceRequest {
            guard let pending else { return self }
            return OverflowRebalanceRequest(
                reason: pending.reason.permitsOrderEnforcement ? pending.reason : reason,
                immediate: pending.immediate || immediate
            )
        }
    }

    /// Match the exact bundle namespace in namespace:title IDs; the colon prevents loose-prefix collisions.
    /// Arm relaunch settling only for apps with tracked status items.
    static nonisolated func tracksMenuBarItem(bundleID: String, in identifiers: Set<String>) -> Bool {
        identifiers.contains { $0.hasPrefix(bundleID + ":") }
    }

    /// Recache mid-pass drags or resets only if the live signature differs; unconditional reruns sustain restriction-reflow storms.
    /// RuntimeMenuBarBackend.itemCacheSignature ignores host-child flicker; newer requests cancel pending reruns.
    private func scheduleCoalescedCacheRerun() {
        coalescedCacheRerunTask?.cancel()
        coalescedCacheRerunTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard !Task.isCancelled else { return }
            let signature = MenuBarBackendProvider.current.itemCacheSignature(items) ?? []
            guard signature != self.cacheCycleState.cachedItemSignature else {
                // Bar has settled, stop the chain rather than recache no-op work.
                return
            }
            await self.cacheItemsRegardless(items.reversed().map(\.windowID))
        }
    }

    /// macOS 27 exposes neither AX elements nor windows for zero-length dividers; synthesize them rather than clearing the cache.
    /// Place dividers at the display's leading edge so real items classify as visible; include always-hidden only when enabled.
    private func synthesizedControlItemPair(
        displayID: CGDirectDisplayID?,
        hiddenControlItemWID: CGWindowID?,
        alwaysHiddenControlItemWID: CGWindowID?
    ) -> ControlItemPair {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let leadingX = displayID.map { CGDisplayBounds($0).minX } ?? (NSScreen.main?.frame.minX ?? 0)
        let syntheticHidden = MenuBarItem(
            tag: .hiddenControlItem,
            windowID: hiddenControlItemWID ?? 0,
            ownerPID: ourPID,
            sourcePID: ourPID,
            bounds: CGRect(x: leadingX, y: 0, width: 0, height: 0),
            title: ControlItem.Identifier.hidden.rawValue,
            isOnScreen: false
        )
        let syntheticAlwaysHidden: MenuBarItem? = {
            guard configuration.isAlwaysHiddenSectionEnabled == true else {
                return nil
            }
            return MenuBarItem(
                tag: .alwaysHiddenControlItem,
                windowID: alwaysHiddenControlItemWID ?? 0,
                ownerPID: ourPID,
                sourcePID: ourPID,
                bounds: CGRect(x: leadingX, y: 0, width: 0, height: 0),
                title: ControlItem.Identifier.alwaysHidden.rawValue,
                isOnScreen: false
            )
        }()
        return ControlItemPair(hidden: syntheticHidden, alwaysHidden: syntheticAlwaysHidden)
    }

    /// Retain the last good cache across control publication gaps to avoid vanishing icons and losing recovery snapshots.
    /// Suppress missing-control alerts during startup registration; report gaps that survive settling.
    private func logMissingControlItems(
        items: [MenuBarItem],
        itemWindowIDs: [CGWindowID],
        hiddenControlItemWID: CGWindowID?,
        alwaysHiddenControlItemWID: CGWindowID?
    ) async {
        if isInStartupSettling {
            MenuBarItemManager.diagLog.debug(
                "cacheItemsRegardless: control items not yet registered by MenuBarAgent (startup settling); retaining last-good cache silently. Items remaining: \(items.count)"
            )
        } else {
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: Missing control item for hidden section (expected tag: \(MenuBarItemTag.hiddenControlItem)); retaining last-good cache. Items remaining: \(items.count), windowIDs: \(itemWindowIDs.count). hiddenControlItemWID=\(hiddenControlItemWID.map { "\($0)" } ?? "nil"), alwaysHiddenControlItemWID=\(alwaysHiddenControlItemWID.map { "\($0)" } ?? "nil")")
            await MainActor.run {
                self.areControlItemsMissing = true
            }
        }
    }

    /// Discover dividers or synthesize them on macOS 27; nil requires retaining the last good cache.
    /// Return the list with discovered dividers removed because this async helper cannot take an inout array.
    private func resolveControlItems(
        items: [MenuBarItem],
        itemWindowIDs: [CGWindowID],
        displayID: CGDirectDisplayID?,
        hiddenControlItemWID: CGWindowID?,
        alwaysHiddenControlItemWID: CGWindowID?
    ) async -> (controlItems: ControlItemPair, items: [MenuBarItem])? {
        var items = items
        if let discoveredControlItems = ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: hiddenControlItemWID,
            alwaysHiddenControlItemWindowID: alwaysHiddenControlItemWID
        ) {
            await MainActor.run {
                self.areControlItemsMissing = false
            }
            return (discoveredControlItems, items)
        }

        if MenuBarBackendProvider.current.canSynthesizeControlItems(snapshotItems: items) {
            let controlItems = synthesizedControlItemPair(
                displayID: displayID,
                hiddenControlItemWID: hiddenControlItemWID,
                alwaysHiddenControlItemWID: alwaysHiddenControlItemWID
            )
            await MainActor.run {
                self.areControlItemsMissing = false
            }
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: control item dividers not enumerable on macOS 27 (zero-width => no AX element); synthesized single-section pair so the layout still populates.")
            return (controlItems, items)
        }

        await logMissingControlItems(
            items: items,
            itemWindowIDs: itemWindowIDs,
            hiddenControlItemWID: hiddenControlItemWID,
            alwaysHiddenControlItemWID: alwaysHiddenControlItemWID
        )
        return nil
    }

    /// Transfer the background continuation to a follow-up pass so waiting callers resume after relocation settles and recaches.
    private func scheduleRecacheAfterRelocation() {
        MenuBarItemManager.diagLog.debug("Relocated new leftmost items; scheduling recache")
        let continuation = backgroundCacheContinuation
        backgroundCacheContinuation = nil
        Task { [weak self] in
            try? await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
            await self?.cacheItemsRegardless(skipRecentMoveCheck: true)
            continuation?.resume()
        }
    }

    /// Rebuild on app, space, move, or layout events, but defer recent moves, active command-drags, and concurrent passes to avoid unstable positions.
    /// Filter clones, reconcile PIDs, and resolve dividers; relocation hands caching off to a settled follow-up pass.
    func cacheItemsRegardless(
        _ currentItemWindowIDs: [CGWindowID]? = nil,
        skipRecentMoveCheck: Bool = false,
        resolveSourcePID: Bool = true,
        skipSavedLayoutApply: Bool = false
    ) async {
        // A cache pass is automatic work even when a Layout edit awaits it, so it never carries the edit's mark.
        await ExplicitLayoutEdit.$isActive.withValue(false) {
            await cacheItemsOutsideLayoutEdit(
                currentItemWindowIDs,
                skipRecentMoveCheck: skipRecentMoveCheck,
                resolveSourcePID: resolveSourcePID,
                skipSavedLayoutApply: skipSavedLayoutApply
            )
        }
    }

    private func cacheItemsOutsideLayoutEdit(
        _ currentItemWindowIDs: [CGWindowID]?,
        skipRecentMoveCheck: Bool,
        resolveSourcePID: Bool,
        skipSavedLayoutApply: Bool
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

        // Coalesce concurrent calls to avoid snapshotting another pass's pre-relocation positions.
        guard await cacheGate.begin() else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: serial cache operation already in progress, coalescing (will rerun)")
            return
        }
        // Await gate release to avoid refusing callers after this pass returns.
        // end() has no cancellation check, so cancelled tasks still release the gate.
        defer {
            let needsRerun = await cacheGate.end()
            // Rerun coalesced drags or resets so layout bars reflect the latest assignments.
            if needsRerun {
                scheduleCoalescedCacheRerun()
            }
        }

        let previousWindowIDs = cacheCycleState.cachedItemWindowIDs
        // Mid-change no connected display is active; keep the cache's display until the topology settles.
        let displayID = DisplayTopology.resolveActiveDisplayID() ?? itemCache.displayID ?? Bridging.getActiveMenuBarDisplayID()
        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: displayID=\(displayID.map { "\($0)" } ?? "nil"), previousWindowIDs count=\(previousWindowIDs.count)")

        let publicationGeneration = layoutPublication.generation
        guard layoutPublication.canPublish(generation: publicationGeneration) else { return }
        var inventory = await MenuBarItemAXProvider.menuBarInventoryConcurrent(freshOnly: true)
        var items = resolveSourcePID ? PositionStoreItemSource.recovering(inventory.items) : inventory.items

        if items.isEmpty {
            // Retry once after a small delay if we got zero items. This can happen
            // due to transient WindowServer glitches or during display reconfigurations.
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: getMenuBarItems returned ZERO items, retrying in 250ms...")
            try? await Task.sleep(for: .milliseconds(250))
            inventory = await MenuBarItemAXProvider.menuBarInventoryConcurrent(freshOnly: true)
            items = resolveSourcePID ? PositionStoreItemSource.recovering(inventory.items) : inventory.items
        }

        guard layoutPublication.canPublish(generation: publicationGeneration), !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("Discarding cache scan superseded by a layout change")
            scheduleCoalescedCacheRerun()
            return
        }
        onScreenItemSnapshot.update(inventory.freshItems.filter(\.isOnScreen))

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: getMenuBarItems returned \(items.count) items")

        // Window Server capture/animation clones have fresh IDs, nil source PIDs, and unstable namespaces; never cache, section, place, or move them.
        // Exclude their IDs from the stored set so clone churn cannot trigger bulk layout restore.
        let cloneWindowIDs = Set(items.filter(\.isSystemClone).map(\.windowID))
        if !cloneWindowIDs.isEmpty {
            let cloneDescriptions = items.filter(\.isSystemClone).map(\.tag.description)
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: dropping \(cloneWindowIDs.count) system clone window(s): \(cloneDescriptions)")
            items.removeAll(where: \.isSystemClone)
        }
        // Backstop AX filtering of macOS 27 overflow chrome; never cache, section, persist, respace, or boundary-repair its chevron.
        if items.contains(where: \.isNativeOverflowControl) {
            let descriptions = items.filter(\.isNativeOverflowControl).map(\.tag.description)
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: dropping native overflow control: \(descriptions)")
            items.removeAll(where: \.isNativeOverflowControl)
        }

        // AX geometry can lag CG updates and mislead SourcePIDCache spatial matching after moves.
        // Prefer source PIDs from a stable prior cycle to protect item identities.
        if resolveSourcePID {
            let previousPIDs = cacheCycleState.cachedItemPIDs
            for i in items.indices {
                let item = items[i]
                guard !item.isControlItem else { continue }
                if let prevPID = previousPIDs[item.windowID],
                   let currentPID = item.sourcePID,
                   currentPID != prevPID
                {
                    // Revert only to a running process; persisting a dead PID would fight correct re-resolution after helper relaunch.
                    let prevRunningApp = NSRunningApplication(processIdentifier: prevPID)
                    guard let prevRunningApp, !prevRunningApp.isTerminated else {
                        MenuBarItemManager.diagLog.debug(
                            "SourcePID changed for windowID \(item.windowID): \(prevPID) -> \(currentPID), previous PID's process is gone, accepting new PID"
                        )
                        continue
                    }

                    MenuBarItemManager.diagLog.warning(
                        "SourcePID changed for windowID \(item.windowID): \(prevPID) -> \(currentPID), reverting to previous PID"
                    )
                    // Rebuild the namespace from the previous PID.
                    let correctedNamespace: MenuBarItemTag.Namespace = if let prevBundleID = prevRunningApp.bundleIdentifier {
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

        // Partial scans can mistake alternating siblings for retitles; learn single-item owners only from complete, fresh inventory.
        if inventory.completed, inventory.hasFreshKnownInventory {
            learnVolatileTitleOwners(previous: itemCache.managedItems, current: &items)
        }

        // Seed corrected source-PID identities for known windows so relocation does not treat them as arrivals.
        // Skip unresolved PIDs to keep the placeholder Control Center namespace out of persisted identities.
        if !previousWindowIDs.isEmpty {
            for item in items where previousWindowIDs.contains(item.windowID) && item.sourcePID != nil {
                let identifier = item.uniqueIdentifier
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

        // Strip clone IDs from the bridging list to match filtered items; the items-based fallback is already clone-free.
        let itemWindowIDs = (currentItemWindowIDs ?? items.reversed().map(\.windowID))
            .filter { !cloneWindowIDs.contains($0) }
        if MenuBarBackendProvider.current.shouldRetainLastGoodCache(
            snapshotItems: items,
            previousCachedItems: itemCache.managedItems
        ) {
            if isInStartupSettling {
                MenuBarItemManager.diagLog.debug(
                    "cacheItemsRegardless: Thaw control items not yet in AX snapshot (startup settling); retaining last-good cache silently. Items remaining: \(items.count), windowIDs: \(itemWindowIDs.count)"
                )
            } else {
                MenuBarItemManager.diagLog.warning(
                    "cacheItemsRegardless: Thaw visible control item missing from AX snapshot; retaining last-good cache. Items remaining: \(items.count), windowIDs: \(itemWindowIDs.count)"
                )
                await MainActor.run { self.areControlItemsMissing = true }
            }
            return
        }
        cacheCycleState.cachedItemWindowIDs = itemWindowIDs
        cacheCycleState.cachedCloneWindowIDs = cloneWindowIDs
        if let signature = MenuBarBackendProvider.current.itemCacheSignature(items) {
            // Update the signature on every recache so periodic polling does not immediately repeat an event-driven rebuild.
            cacheCycleState.cachedItemSignature = signature
        }

        await MainActor.run {
            self.pruneClickOperationTimeouts(keeping: Set(items.map(\.tag)))
        }

        // Use ControlItem window IDs when macOS 26+ tag and title lookups fail.
        let controlItemWindowIDs = liveControlItemWindowIDs()
        let hiddenControlItemWID = controlItemWindowIDs.hidden
        let alwaysHiddenControlItemWID = controlItemWindowIDs.alwaysHidden

        guard let resolved = await resolveControlItems(
            items: items,
            itemWindowIDs: itemWindowIDs,
            displayID: displayID,
            hiddenControlItemWID: hiddenControlItemWID,
            alwaysHiddenControlItemWID: alwaysHiddenControlItemWID
        ) else { return }
        items = resolved.items
        let controlItems = resolved.controlItems

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: found control items, hidden windowID=\(controlItems.hidden.windowID), alwaysHidden=\(controlItems.alwaysHidden.map { "\($0.windowID)" } ?? "nil")")

        guard !Task.isCancelled, layoutPublication.canPublish(generation: publicationGeneration) else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled or superseded after control item discovery")
            return
        }

        // Partial inventory can populate the editor, but cannot authorize
        // boundary repairs or replace saved order with retained geometry.
        lastKnownControlItems = controlItems
        if !inventory.hasFreshKnownInventory {
            await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID, publicationGeneration: publicationGeneration, observationOnly: true)
            return
        }

        // Skip structural policy while login items repopulate MenuBarAgent positions in waves.
        // After settling, macOS 27 ambient passes remain observation-only; legacy backends enforce dividers.
        if isInStartupSettling {
            MenuBarItemManager.diagLog.debug(
                "cacheItemsRegardless: startup settling active, deferring structural control order"
            )
        } else {
            await enforceControlItemOrder(
                controlItems: controlItems,
                items: items,
                reason: .ambientCacheRefresh
            )
            // Ambient enforcement only observes drift; schedule debounced normalization rather than waiting for explicit reveal or repair.
            scheduleStructuralNormalizationIfControlItemsOutOfOrder(
                controlItems: controlItems,
                items: items,
                displayID: displayID
            )
        }

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled before relocateNewLeftmostItems")
            return
        }

        if await relocateNewLeftmostItems(
            items,
            controlItems: controlItems
        ) {
            scheduleRecacheAfterRelocation()
            return
        }

        // Defer restore until the final settling-end cache pass to avoid cascading moves during login or rapid app restarts.
        guard !isInStartupSettling else {
            await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID, publicationGeneration: publicationGeneration)
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: startup settling active, skipping restore")
            return
        }

        // Retain resolved dividers for synchronous drop-handler pre-seating, which cannot afford another AX walk.
        await MainActor.run {
            self.lastKnownControlItems = controlItems
        }

        // applySavedLayout owns cooldowns; profile apply marks restoring and recaches, while rejection leaves current-cache persistence enabled.
        // Skip post-apply refresh reentry: transient Control Center window-ID churn would otherwise loop on no-op applies.
        if !skipSavedLayoutApply {
            let didApplySavedLayout = await applySavedLayout(
                items: items,
                previousWindowIDs: previousWindowIDs,
                controlItems: controlItems,
                previousDisplayID: itemCache.displayID,
                currentDisplayID: displayID
            )
            if didApplySavedLayout {
                backgroundCacheContinuation?.resume()
                backgroundCacheContinuation = nil
                return
            }
        }

        await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID, publicationGeneration: publicationGeneration)

        // Keep resolved PIDs as the next cycle's error baseline; resolveSourcePID=false fast restores must not overwrite it.
        if resolveSourcePID {
            let newPIDs = Dictionary(
                uniqueKeysWithValues: items.compactMap { item in
                    item.sourcePID.map { (item.windowID, $0) }
                }
            )
            cacheCycleState.cachedItemPIDs = newPIDs
        }

        // Accept late profile arrivals where they land; observation does not authorize undoing changes (LayoutChangeReason).

        await MainActor.run {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: finished, cache now has \(self.itemCache.managedItems.count) managed items")
        }
    }

    /// Require a continuously stable signature to avoid icon reorders from macOS 27 AX, restriction, and clone flapping; two quick samples are insufficient.
    /// Gate only autonomous polls; app events and drags recache immediately.
    /// - Parameters:
    ///   - firstSeen: When pending was first observed (nil if no candidate).
    ///   - now: The current instant, injected for testability.
    ///   - grace: How long a difference must hold before it confirms.
    /// - Returns: Whether to recache and the candidate/first-seen instant to retain; both nil clears the gate.
    static func signatureRecacheDecision(
        cached: [String],
        current: [String],
        pending: [String]?,
        firstSeen: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        grace: Duration
    ) -> (recache: Bool, newPending: [String]?, newFirstSeen: ContinuousClock.Instant?) {
        // Live state matches the cache: nothing to do, drop any stale candidate.
        guard current != cached else {
            return (recache: false, newPending: nil, newFirstSeen: nil)
        }
        // Preserve the streak's start until the same difference holds for the full grace window.
        if let pending, let firstSeen, pending == current {
            if now - firstSeen >= grace {
                return (recache: true, newPending: nil, newFirstSeen: nil)
            }
            return (recache: false, newPending: current, newFirstSeen: firstSeen)
        }
        // First sighting, or the difference itself changed: (re)start the clock.
        return (recache: false, newPending: current, newFirstSeen: now)
    }

    /// Gate expensive AX walks with a cheap window-list comparison, then require a stable identity difference before rebuilding.
    func cacheItemsIfNeeded() async {
        // Window-list changes cover additions, removals, moves, reveals, and hides without an AX signature walk.
        // Use the unfiltered superset to avoid per-window IPC; off-space changes merely cost an extra walk.
        let rawWindowIDs = Bridging.getMenuBarWindowList(option: [])
        let cloneIDs = cacheCycleState.cachedCloneWindowIDs
        let cheap = cloneIDs.isEmpty
            ? rawWindowIDs
            : rawWindowIDs.filter { !cloneIDs.contains($0) }
        if let last = periodicWindowListSignature, last == cheap {
            return
        }
        MenuBarItemManager.diagLog.debug(
            "cacheItemsIfNeeded: cheap window-list gate changed (\(periodicWindowListSignature?.count ?? -1) -> \(cheap.count)); walking"
        )
        periodicWindowListSignature = cheap

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        let signature = MenuBarBackendProvider.current.itemCacheSignature(items) ?? []
        // Assertion-backed menu bar items use synthetic window IDs, so
        // compare stable visual-order identity instead of WindowServer IDs.
        let cachedSignature = cacheCycleState.cachedItemSignature
        let decision = Self.signatureRecacheDecision(
            cached: cachedSignature,
            current: signature,
            pending: pendingItemSignatureCandidate,
            firstSeen: pendingItemSignatureFirstSeen,
            now: .now,
            grace: Constants.MenuBarTuning.signatureStabilityGrace
        )
        pendingItemSignatureCandidate = decision.newPending
        pendingItemSignatureFirstSeen = decision.newFirstSeen
        if decision.recache {
            MenuBarItemManager.diagLog.debug("cacheItemsIfNeeded: item identities changed and confirmed (\(cachedSignature.count) cached vs \(signature.count) current), triggering recache")
            await cacheItemsRegardless(items.reversed().map(\.windowID))
        } else if decision.newPending != nil {
            // AX-only changes may not alter the window list; drop the cheap gate so the next tick can confirm them.
            periodicWindowListSignature = nil
            MenuBarItemManager.diagLog.debug("cacheItemsIfNeeded: item identities differ (\(cachedSignature.count) cached vs \(signature.count) current); deferring recache until the difference holds for the stability grace")
        }
    }
}
