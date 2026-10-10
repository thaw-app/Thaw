//
//  MenuBarItemManager+StartupSettling.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

// MARK: - Startup settling

extension MenuBarItemManager {
    /// Starts a settling period during which restore and section-order saves
    /// are suppressed. The settling task polls cacheItemsRegardless until
    /// the menu bar has stabilized, then runs two final cache passes that
    /// trigger the saved-layout restore.
    ///
    /// With expectedBundleIDs, settling ends once all of them are cached;
    /// otherwise once the managed-item count holds. Both also need sourcePIDs
    /// resolved. maxDuration is generous because some apps take tens of
    /// seconds to reattach. On re-entry the later deadline wins.
    func startSettlingPeriod(
        reason: String,
        expectedBundleIDs: Set<String> = [],
        maxDuration: Duration = .seconds(60)
    ) {
        let mergedExpected = settlingExpectedBundleIDs.union(expectedBundleIDs)
        let incomingKind: SettlingKind = if !mergedExpected.isEmpty {
            .expectedSet
        } else if reason == "performSetup" {
            .cold
        } else if reason.hasPrefix("spacingRelaunch") {
            .preflight
        } else {
            .event
        }

        // A weaker settling must not demote a stronger one in flight: a
        // preflight yields to everything else, and a display change or launch
        // yields to the boot and relaunch waits. Keep the merged expected set.
        if let existing = settlingKind,
           Self.settlingYields(incoming: incomingKind, to: existing)
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
        // The cancelled task exits without touching shared state.
        startupSettlingTask?.cancel()
        isInStartupSettling = true
        postRestrictionRepairTask?.cancel()
        postRestrictionRepairTask = nil
        postRestrictionRepairNeedsRerun = false
        structuralNormalizationTask?.cancel()
        structuralNormalizationTask = nil
        repairs.withdraw(.postRestrictionRepair)
        repairs.withdraw(.structuralNormalization)
        MenuBarItemManager.diagLog.debug("\(reason): settling period started (max duration: \(maxDuration))")
        // @MainActor ensures the flag flip and final cache call are never
        // interleaved with notification-triggered cache cycles between them.
        startupSettlingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.initialCacheTask?.value

            let stableTarget = 3
            var lastSeenCount = -1
            var stablePolls = 0
            let waitingFor = mergedExpected
            let useExpectedSet = !waitingFor.isEmpty
            let settlingStartedAt = ContinuousClock.now
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
                let minimumElapsed = settlingStartedAt.duration(to: .now) >= Self.startupMinimumSettlingDuration
                let hostReady = menuBarHostItemsReady(in: itemCache)

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
                    if stillMissing.isEmpty,
                       pidsOK,
                       minimumElapsed,
                       hostReady
                    {
                        MenuBarItemManager.diagLog.debug(
                            "\(reason): all \(waitingFor.count) expected bundle ID(s) reattached, ending early"
                        )
                        break
                    }
                    MenuBarItemManager.diagLog.debug(
                        "\(reason): \(stillMissing.count) bundle ID(s) still missing: \(stillMissing.sorted().joined(separator: ", "))"
                    )
                } else {
                    if pidsOK,
                       managedCount == lastSeenCount,
                       minimumElapsed,
                       hostReady
                    {
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
                        } else if !minimumElapsed {
                            MenuBarItemManager.diagLog.debug(
                                "\(reason): count stable but minimum settle \(Self.startupMinimumSettlingDuration) not elapsed yet"
                            )
                        } else if !hostReady {
                            MenuBarItemManager.diagLog.debug(
                                "\(reason): waiting for menu bar host modules (MenuBarAgent / BentoBox)"
                            )
                        }
                        stablePolls = 0
                        lastSeenCount = managedCount
                    }
                }

                do {
                    try await Task.sleep(
                        for: Constants.MenuBarTuning.startupSettlingPollInterval,
                        tolerance: .milliseconds(100)
                    )
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
            // A bar arranged by hand while Thaw was not running, or under an
            // older build, has to be read once before its sections can be.
            adoptObservedMembership(reason: "settled launch")

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

            // The active display's profile, not savedSectionOrder, is the truth
            // at launch. Await it so applySavedLayout below cannot race it.
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
            // Moves stamped during settling would otherwise skip both passes
            // through the recent-move cooldown.
            await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: false)
            // Resolves source PIDs for later readers.
            await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: true)

            // Repair only after the startup inventory and saved layout have
            // settled; intermediate login-item frames can overlap or be parked.
            schedulePostRestrictionRepair(cause: .settled)
            scheduleStructuralNormalization(cause: .settled)

            if reason == "performSetup" {
                scheduleStartupLateItemRecheck()
            }
        }
    }

    static func settlingYields(incoming: SettlingKind, to existing: SettlingKind) -> Bool {
        switch incoming {
        case .preflight: existing != .preflight
        case .event: existing == .cold || existing == .expectedSet
        case .cold, .expectedSet: false
        }
    }

    /// Re-checks for status items that register after the cold-boot settling
    /// window (already-running apps with late NSStatusItem attachment).
    private func scheduleStartupLateItemRecheck() {
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
}
