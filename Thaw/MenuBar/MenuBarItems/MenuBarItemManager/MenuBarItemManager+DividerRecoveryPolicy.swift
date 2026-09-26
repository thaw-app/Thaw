//
//  MenuBarItemManager+DividerRecoveryPolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

extension MenuBarItemManager {
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
}
