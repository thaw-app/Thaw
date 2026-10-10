//
//  MenuBarItemManager+HostRecovery.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - Host Recovery

extension MenuBarItemManager {
    /// A brief period in which missing dividers mean Control Center is still
    /// re-hosting status items, not that Thaw should recreate them.
    static nonisolated let controlCenterRelaunchGrace: Duration = .seconds(20)

    static nonisolated func shouldCountControlItemLookupFailure(
        hostUptime: Duration?,
        suppressAutomaticMoves: Bool = false,
        grace: Duration = controlCenterRelaunchGrace
    ) -> Bool {
        // Layout-editor refreshes must not advance recovery or trigger its side effects.
        guard !suppressAutomaticMoves else { return false }
        guard let hostUptime else { return true }
        return hostUptime >= grace
    }

    static func controlCenterGeneration() -> ProcessGeneration? {
        SourcePIDSeedStore.currentControlCenterGeneration()
    }

    static nonisolated func controlCenterUptime(
        generation: ProcessGeneration?,
        now: Date = .now
    ) -> Duration? {
        generation.map { .seconds(max(0, now.timeIntervalSince($0.launchDate))) }
    }

    /// Re-arms divider recovery when Control Center restarts; the new host
    /// builds its windows from scratch.
    @discardableResult
    static nonisolated func resetControlItemLookupEpisodeIfHostChanged(
        previous: ProcessGeneration?,
        current: ProcessGeneration?,
        failureStreak: inout Int,
        alreadyRebuilt: inout Bool
    ) -> Bool {
        guard let current, current != previous else { return false }
        failureStreak = 0
        alreadyRebuilt = false
        return true
    }

    /// Rebuilds the hidden divider after repeated evidence that stale geometry
    /// closed the hidden span. The saved order is untouched, so the next pass restores it.
    ///
    /// managedItemCount decides whether the rebuild may also re-stamp the
    /// seeded position. See canSeedRebuiltDividerPosition(managedItemCount:).
    func recoverCollapsedHiddenSectionIfNeeded(
        hiddenSectionHasRoom: Bool,
        controlItems: ControlItemPair,
        managedItemCount: Int
    ) -> Bool {
        // Only authoritative readings may touch the recovery episode.
        guard controlItems.canRepositionControlItems else {
            return false
        }

        guard !hiddenSectionHasRoom else {
            hiddenSectionCollapseStreak = 0
            didRecoverHiddenSectionForCurrentCollapse = false
            return false
        }

        hiddenSectionCollapseStreak += 1
        guard Self.shouldRecoverCollapsedHiddenSection(
            consecutiveCollapsedReadings: hiddenSectionCollapseStreak,
            alreadyRecovered: didRecoverHiddenSectionForCurrentCollapse
        ),
            let hiddenControlItem = appState?.menuBarManager.controlItem(withName: .hidden)
        else {
            return false
        }

        didRecoverHiddenSectionForCurrentCollapse = true
        let seed = Self.seedForRebuiltDivider(
            managedItemCount: managedItemCount,
            storedPositions: Self.currentStoredDividerPositions()
        )
        MenuBarItemManager.diagLog.warning(
            "Hidden section remained collapsed for \(hiddenSectionCollapseStreak) authoritative cache passes; rebuilding H_ctrl\(Self.seedDescription(seed))"
        )
        hiddenControlItem.recreateStatusItem(preferredPosition: seed.preferredPosition)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            await self?.cacheItemsRegardless(options: .init(skipRecentMoveCheck: true))
        }
        return true
    }

    /// Why a cycle is asking the parked-divider recovery to look at H_ctrl.
    ///
    /// A stranded divider makes the applies refuse before Phase 1, so a refusal
    /// counts like a mismatch; otherwise recovery could never trigger (#978).
    nonisolated enum ParkedDividerTrigger {
        /// Phase 1 found items on the wrong side of H_ctrl.
        case boundaryMismatch(Int)
        /// An apply refused upstream because the hidden section read as
        /// having no room between the dividers. source names the guard.
        case refusedApply(source: String)

        /// Whether this cycle actually needed the divider on the bar. A
        /// mismatch of zero is a healthy cycle; a refusal never is.
        var needsDividerOnBar: Bool {
            switch self {
            case let .boundaryMismatch(count): count > 0
            case .refusedApply: true
            }
        }

        var logDescription: String {
            switch self {
            case let .boundaryMismatch(count): "\(count)-item boundary mismatch"
            case let .refusedApply(source): "refused \(source) apply"
            }
        }
    }

    /// Rebuilds an authoritatively identified hidden divider after it remains
    /// parked through repeated layout cycles that need it on the bar.
    ///
    /// "Parked" means no edge of the frame is on any display. A healthy
    /// collapsed H_ctrl already reaches offscreen, so one edge isn't enough (#978).
    ///
    /// managedItemCount and the stored control item positions decide what
    /// the rebuild does with the autosaved position. See
    /// MenuBarItemManager/seedForRebuiltDivider(managedItemCount:storedPositions:).
    func recoverParkedHiddenDividerIfNeeded(
        trigger: ParkedDividerTrigger,
        hiddenControlItem: MenuBarItem,
        screenFrames: [CGRect],
        managedItemCount: Int
    ) -> Bool {
        guard trigger.needsDividerOnBar,
              LayoutSolver.isFullyOffScreen(bounds: hiddenControlItem.bounds, screenFrames: screenFrames)
        else {
            resetParkedHiddenDividerRecovery()
            return false
        }

        parkedHiddenDividerMismatchStreak += 1
        guard Self.shouldRecoverParkedHiddenDivider(
            consecutiveMismatchReadings: parkedHiddenDividerMismatchStreak,
            alreadyRecovered: didRecoverParkedHiddenDividerForCurrentMismatch
        ),
            let hiddenControl = appState?.menuBarManager.controlItem(withName: .hidden)
        else {
            return false
        }

        didRecoverParkedHiddenDividerForCurrentMismatch = true
        let seed = MenuBarItemManager.seedForRebuiltDivider(
            managedItemCount: managedItemCount,
            storedPositions: MenuBarItemManager.currentStoredDividerPositions()
        )
        MenuBarItemManager.diagLog.warning(
            "H_ctrl remained parked through \(parkedHiddenDividerMismatchStreak) authoritative applies (\(trigger.logDescription)); rebuilding it\(MenuBarItemManager.seedDescription(seed))"
        )
        hiddenControl.recreateStatusItem(preferredPosition: seed.preferredPosition)

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            // The failed batch may have stamped the move cooldown; bypass it so
            // applySavedLayout verifies the fresh divider.
            await self?.cacheItemsRegardless(
                options: .init(
                    skipRecentMoveCheck: true,
                    bypassSavedLayoutCooldown: true
                )
            )
        }
        return true
    }

    /// Clears the parked-divider streak, so the next strand starts counting
    /// from zero and is allowed its own rebuild.
    ///
    /// Separate because Phase 1 also clears it; clearing on a zero mismatch
    /// alone reset a stranded divider's streak every cycle (#978).
    func resetParkedHiddenDividerRecovery() {
        parkedHiddenDividerMismatchStreak = 0
        didRecoverParkedHiddenDividerForCurrentMismatch = false
    }
}
