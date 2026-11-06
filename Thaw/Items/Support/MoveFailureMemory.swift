//
//  MoveFailureMemory.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Which macOS 27 section-order drags failed lately, so the same doomed drag is not retried
/// every cache cycle.
///
/// An anchored system item (such as Sound or Control Center) can sit between two items that a
/// saved order wants adjacent, which makes the move unachievable by the synthetic Command-drag.
/// Retrying it hijacks the cursor and disturbs the dragged item's AX and rendering state, so
/// two memories hold it back. The backoff is keyed by the desired order as well as the move.
/// An overflowing bar conceals a different set each cycle, which changes the order and so mints
/// a fresh backoff key every pass; the breaker is keyed by the move alone, so repeated failures
/// trip a cooldown that order churn cannot bypass. The breaker gates automatic passes only: the
/// caller exempts a user-initiated reorder.
nonisolated struct MoveFailureMemory {
    /// How long to suppress retrying a move after it fails under one desired order, before
    /// giving the achievable-order solver another chance.
    static let backoff: Duration = .seconds(30)

    /// Failures in a row for one move that trip the breaker.
    static let itemFailureThreshold = 3

    /// How long a move stays suppressed once the breaker trips.
    static let itemFailureCooldown: Duration = .seconds(30)

    /// One planned drag: an item, and the side of the target it should land on.
    struct Move: Equatable {
        /// item|side|target, deliberately without the desired order.
        fileprivate let itemKey: String

        /// Uses uniqueIdentifier rather than logString for both items: the latter embeds the
        /// item's transient windowID, which would defeat both memories the moment either
        /// item's synthetic windowID churns between cycles.
        init(item: MenuBarItem, destination: MoveDestination) {
            let side = switch destination {
            case .leftOfItem: "leftOf"
            case .rightOfItem: "rightOf"
            }
            itemKey = "\(item.uniqueIdentifier)|\(side)|\(destination.targetItem.uniqueIdentifier)"
        }

        fileprivate func orderKey(desiredOrder: [String]) -> String {
            "\(desiredOrder.joined(separator: ">"))|\(itemKey)"
        }
    }

    private struct ItemRecord {
        var count: Int
        var last: ContinuousClock.Instant
    }

    private var orderFailures: [String: ContinuousClock.Instant] = [:]
    private var itemFailures: [String: ItemRecord] = [:]

    /// Whether the move failed under this desired order within the backoff window.
    func isBackingOff(
        from move: Move,
        desiredOrder: [String],
        now: ContinuousClock.Instant = .now
    ) -> Bool {
        guard let last = orderFailures[move.orderKey(desiredOrder: desiredOrder)] else { return false }
        return now - last < Self.backoff
    }

    /// Whether the move has failed often enough, recently enough, to be suppressed.
    func isBreakerTripped(for move: Move, now: ContinuousClock.Instant = .now) -> Bool {
        guard let record = itemFailures[move.itemKey] else { return false }
        return record.count >= Self.itemFailureThreshold
            && now - record.last < Self.itemFailureCooldown
    }

    /// Failures in a row the breaker holds against the move.
    func failureCount(for move: Move) -> Int {
        itemFailures[move.itemKey]?.count ?? 0
    }

    /// Files one failed drag against both memories. A gap longer than the cooldown restarts
    /// the breaker's streak so stale failures cannot accumulate.
    mutating func recordFailure(
        of move: Move,
        desiredOrder: [String],
        now: ContinuousClock.Instant = .now
    ) {
        backOff(from: move, desiredOrder: desiredOrder, now: now)
        var record = itemFailures[move.itemKey] ?? ItemRecord(count: 0, last: now)
        if now - record.last >= Self.itemFailureCooldown {
            record.count = 0
        }
        record.count += 1
        record.last = now
        itemFailures[move.itemKey] = record
    }

    /// Starts the backoff without counting a failure, for a move that is skipped before any
    /// drag is tried.
    mutating func backOff(
        from move: Move,
        desiredOrder: [String],
        now: ContinuousClock.Instant = .now
    ) {
        orderFailures[move.orderKey(desiredOrder: desiredOrder)] = now
    }

    /// Clears both memories for a move that landed, which proves the target reachable.
    mutating func recordSuccess(of move: Move, desiredOrder: [String]) {
        orderFailures[move.orderKey(desiredOrder: desiredOrder)] = nil
        itemFailures[move.itemKey] = nil
    }
}
