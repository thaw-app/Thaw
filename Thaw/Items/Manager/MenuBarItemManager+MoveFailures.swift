//
//  MenuBarItemManager+MoveFailures.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

// MARK: - Move failures

extension MenuBarItemManager {
    /// Item-scoped circuit breaker for automatic macOS 27 section-order drags.
    ///
    /// The recentMoveFailures backoff keys on the full desiredOrder
    /// string, so overflow churn defeats it: when
    /// applyOverflowRebalance conceals a different set each cycle, the
    /// order string and so the failure key change every time, and the same
    /// multi-second failing drag re-fires indefinitely. This ledger keys only
    /// on item, side and target, so repeated verify failures for one move trip
    /// a cooldown that order churn cannot bypass. It gates automatic passes
    /// only; a user-initiated reorder is never suppressed (see isUserInitiated
    /// on applySectionItemOrder).
    struct ItemMoveFailureRecord {
        var count: Int
        var last: ContinuousClock.Instant
    }

    /// Builds the item-scoped breaker key: item|side|target, deliberately
    /// omitting desiredOrder so the overflow churn cannot mint a fresh key.
    static func itemMoveFailureKey(
        item: MenuBarItem,
        destination: MoveDestination
    ) -> String {
        let side = switch destination {
        case .leftOfItem: "leftOf"
        case .rightOfItem: "rightOf"
        }
        return "\(item.uniqueIdentifier)|\(side)|\(destination.targetItem.uniqueIdentifier)"
    }

    /// Whether the item-scoped breaker is currently tripped for key.
    func isItemMoveCircuitBreakerTripped(key: String) -> Bool {
        guard let record = recentItemMoveFailures[key] else { return false }
        return record.count >= Self.itemMoveFailureThreshold
            && ContinuousClock.now - record.last < Self.itemMoveFailureCooldown
    }

    /// Files one automatic-drag verify-failure against key. A gap longer than
    /// the cooldown restarts the streak so stale failures cannot accumulate.
    func recordItemMoveFailure(key: String) {
        var record = recentItemMoveFailures[key]
            ?? ItemMoveFailureRecord(count: 0, last: .now)
        if ContinuousClock.now - record.last >= Self.itemMoveFailureCooldown {
            record.count = 0
        }
        record.count += 1
        record.last = .now
        recentItemMoveFailures[key] = record
    }

    /// Clears the breaker for key, a landed move proves the target reachable.
    func clearItemMoveFailure(key: String) {
        recentItemMoveFailures.removeValue(forKey: key)
    }

    /// Builds the backoff key for a planned macOS 27 section-order move.
    ///
    /// Uses uniqueIdentifier rather than logString for both items: the
    /// latter embeds the item's transient windowID, which would defeat the
    /// backoff the moment either item's synthetic windowID churns between
    /// cycles even though the logical move being retried hasn't changed.
    static func moveFailureKey(
        item: MenuBarItem,
        destination: MoveDestination,
        desiredOrder: [String]
    ) -> String {
        let side = switch destination {
        case .leftOfItem: "leftOf"
        case .rightOfItem: "rightOf"
        }
        return "\(desiredOrder.joined(separator: ">"))|\(item.uniqueIdentifier)|\(side)|\(destination.targetItem.uniqueIdentifier)"
    }
}
