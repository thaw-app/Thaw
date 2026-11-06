//
//  MenuBarItemManager+StartupSettling.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

// MARK: - Bar settling host

extension MenuBarItemManager {
    /// Polls and the work after settling run on the main actor, so no notification-triggered cache
    /// cycle slips between the flag flip and the final passes.
    func makeSettlingHost() -> BarSettling.Host {
        BarSettling.Host(
            awaitInitialRead: { [weak self] in await self?.initialCacheTask?.value },
            sample: { [weak self] in await self?.settlingSample() ?? BarSettling.Sample() },
            didStart: { [weak self] in
                guard let self else { return }
                PendingPassTeardown.callOff([.postRestrictionRepair, .structuralNormalization], of: self, on: repairs)
            },
            didSettle: { [weak self] in await self?.finishSettling($0) }
        )
    }

    private func settlingSample() async -> BarSettling.Sample {
        await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: true)
        let items = itemCache.managedItems
        return BarSettling.Sample(
            managedCount: items.count,
            unresolvedPIDs: SettlingSourcePIDs.unresolvedCount(in: items),
            hostReady: menuBarHostItemsReady(in: itemCache),
            bundleIDs: Set(items.compactMap { item in
                if case let .string(bid) = item.tag.namespace {
                    return bid
                }
                return nil
            }),
            barQuiet: savedOrderMirrorGate.isQuiet()
        )
    }

    private func finishSettling(_ ending: BarSettling.Ending) async {
        let reason = ending.disturbance.label
        // A bar arranged by hand while Thaw was not running, or under an
        // older build, has to be read once before its sections can be.
        // Only items with no section yet: Layout's sections win over stale weights.
        if ending.adoptsObservedMembership {
            adoptObservedMembership(reason: "settled launch", keepingAuthored: true)
        }

        // Once per launch, after login items register: hygiene asks
        // NSWorkspace which apps exist. Latched because profile applies
        // also settle through here.
        if !didRunPositionStoreHygiene {
            didRunPositionStoreHygiene = true
            repairs.request(.storeHygiene, cause: .settled)
            if let hold = await repairs.enter(.storeHygiene) {
                PositionStoreHygiene.pruneCurrentStore(permit: StoreWritePermit(hold))
                repairs.leave(hold)
            }
        }

        await settleActiveProfile(reason: reason)

        MenuBarItemManager.diagLog.debug(
            "\(reason): running fast restore without sourcePID resolution"
        )
        // Moves stamped during settling would otherwise skip both passes
        // through the recent-move cooldown.
        await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: false)
        // Resolves source PIDs for later readers.
        await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: true)

        // Repair only after the startup inventory and saved layout have
        // settled; intermediate login-item frames can overlap or be parked.
        schedulePostRestrictionRepair(cause: .settled)
        scheduleStructuralNormalization(cause: .settled)

        if ending.disturbance == .thawLaunched {
            scheduleStartupLateItemRecheck()
        }
    }

    /// Re-checks for status items that register after the cold-boot settling
    /// window (already-running apps with late NSStatusItem attachment), then
    /// for login items that add theirs a minute or more after launch.
    private func scheduleStartupLateItemRecheck() {
        LateLoginArrivals.schedule(for: self)
        Task { @MainActor [weak self] in
            // Many apps attach their status item 2–5 s after start, with no
            // launch notification since they were already running.
            try? await Task.sleep(for: .seconds(2.5))
            await self?.cacheItemsIfNeeded()
            try? await Task.sleep(for: .seconds(2.5))
            await self?.cacheItemsIfNeeded()
        }
    }

    /// Whether the menu bar host modules (MenuBarAgent / BentoBox) have
    /// appeared in the cache.
    private func menuBarHostItemsReady(in cache: ItemCache) -> Bool {
        cache.managedItems.contains {
            $0.tag.namespace == .menuBarAgent || $0.tag.isBentoBox
        }
    }

    /// Only a profile other than the one in place is applied, so drags made since survive. An apply started
    /// here is awaited so applySavedLayout can't race it; one already running waits on this settle's task,
    /// so awaiting it here would deadlock.
    private func settleActiveProfile(reason: String) async {
        guard let profiles = appState?.profileManager else { return }
        switch ProfileSettleReapply.Record().settle(
            activeProfileID: profiles.activeProfileID,
            pendingApplyProfileID: profiles.pendingApplyProfileID
        ) {
        case .reapply:
            MenuBarItemManager.diagLog.info("\(reason): applying active display profile after settling")
            profiles.reapplyActiveProfile()
            await profiles.layoutTask?.value
        case .leavePendingApply, .keep:
            break
        }
    }
}
