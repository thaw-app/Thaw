//
//  MoveCircuitBreaker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Trips when automatic reordering runs away, and pauses it.
///
/// Stops icon dancing (the bar keeps putting a dragged item back, so the
/// same item is dragged again) and cursor kidnapping (failing moves keep
/// holding the hidden pointer). A profile apply drags many items once each,
/// so the signals are repeats of one item and failed moves, not raw count.
///
/// Counted in a sliding window. Past a limit, automatic moves are refused for
/// a cooldown that grows with each trip. User moves are never counted.
///
/// Also owns the two coarser rules: how many unfinished bulk applies in a row
/// ration the next one, and how many failures in a row end a batch.
@MainActor
final class MoveCircuitBreaker {
    enum Signal: Equatable {
        /// An automatic drag of the item with this identifier. The "dancing"
        /// signal when one identifier repeats.
        case move(identifier: String)
        /// An automatic move that gave up. The "kidnap" signal.
        case failedMove
    }

    /// How far back the counts look.
    static nonisolated let window: Duration = .seconds(60)
    /// Automatic drags of one item allowed in the window before tripping.
    /// A pass that seats an item, a rescue and a re-apply stay under it.
    static nonisolated let sameItemMoveLimit = 4
    /// Failed automatic moves allowed in the window before tripping.
    static nonisolated let failureLimit = 8
    /// First cooldown after a trip.
    static nonisolated let initialCooldown: Duration = .seconds(60)
    /// Ceiling on the exponential backoff.
    static nonisolated let maximumCooldown: Duration = .seconds(600)
    /// How long without a trip before the backoff resets to the initial value.
    static nonisolated let backoffResetInterval: Duration = .seconds(300)

    private struct Event {
        let at: ContinuousClock.Instant
        let signal: Signal
    }

    private let now: () -> ContinuousClock.Instant
    private var events: [Event] = []
    private var openUntil: ContinuousClock.Instant?
    private var lastTripAt: ContinuousClock.Instant?
    private var cooldown: Duration = MoveCircuitBreaker.initialCooldown
    private var trips = 0

    /// Bulk applies in a row that ended with planned moves unenacted.
    private(set) var unfinishedBulkApplyStreak = 0
    private var lastUnfinishedBulkApplyAt: ContinuousClock.Instant?

    init(now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.now = now
    }

    /// Whether automatic moves are paused right now.
    var isOpen: Bool {
        guard let openUntil else { return false }
        return now() < openUntil
    }

    /// Diagnostics for the log.
    var stateDescription: String {
        let openFor = openUntil.map { max(Duration.zero, now().duration(to: $0)) } ?? .zero
        return "trips=\(trips) open=\(isOpen) openFor=\(openFor) window=\(events.count) "
            + "cooldown=\(cooldown) unfinishedBulkApplies=\(unfinishedBulkApplyStreak)"
    }

    /// Whether an automatic bulk apply may start now. Closed breaker first,
    /// then the unfinished-apply ration.
    var permitsAutomaticBulkApply: Bool {
        !isOpen && Self.bulkApplyPermitted(
            consecutiveUnfinishedBatches: unfinishedBulkApplyStreak,
            lastUnfinishedBatchAt: lastUnfinishedBulkApplyAt,
            now: now()
        )
    }

    /// Records how a bulk apply ended. A clean one, or a user move, resets
    /// the streak.
    func noteBulkApplyOutcome(unenactedMoveCount: Int) {
        guard unenactedMoveCount > 0 else {
            unfinishedBulkApplyStreak = 0
            lastUnfinishedBulkApplyAt = nil
            return
        }
        unfinishedBulkApplyStreak += 1
        lastUnfinishedBulkApplyAt = now()
    }

    /// Whether an automatic bulk apply may dispatch given how the recent ones
    /// ended.
    ///
    /// One retry after a failed batch. Two in a row means the bar refuses moves
    /// (#900), so after that it's one attempt per cooldown, each costing a
    /// hidden cursor (#899). Past the hard cap it waits for a clean apply or a
    /// user move.
    static nonisolated func bulkApplyPermitted(
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

    /// Whether a move batch should abandon its remaining moves.
    ///
    /// Each failing move burns its full budget with the cursor hidden (#899).
    /// Three in a row means the bar is refusing drags. Consecutive, not total:
    /// a success resets the run.
    static nonisolated func batchShouldAbandon(
        consecutiveFailures: Int,
        threshold: Int = 3
    ) -> Bool {
        consecutiveFailures >= threshold
    }

    /// Records an automatic move and trips when a limit is crossed. Returns
    /// whether the breaker is open afterwards.
    @discardableResult
    func note(_ signal: Signal) -> Bool {
        let now = now()
        prune(before: now)
        events.append(Event(at: now, signal: signal))
        if isOpen {
            return true
        }

        var reasons = [String]()
        if case let .move(identifier) = signal {
            let repeats = events.count { $0.signal == signal }
            if repeats > Self.sameItemMoveLimit {
                reasons.append("\(repeats) moves of \(identifier)")
            }
        }
        let failures = events.count { $0.signal == .failedMove }
        if failures > Self.failureLimit {
            reasons.append("\(failures) failed moves")
        }
        guard !reasons.isEmpty else { return false }

        openFor(reason: reasons.joined(separator: ", "), now: now)
        return true
    }

    /// Opens the breaker for the current cooldown and doubles it for next time.
    private func openFor(reason: String, now: ContinuousClock.Instant) {
        // A trip long enough after the last one means the bar had settled, so
        // the backoff starts over rather than punishing a one-off.
        if let lastTripAt, lastTripAt.duration(to: now) > Self.backoffResetInterval {
            cooldown = Self.initialCooldown
        }
        lastTripAt = now
        trips += 1
        openUntil = now.advanced(by: cooldown)
        MenuBarItemManager.diagLog.error(
            "Move circuit breaker tripped: \(reason) within \(Self.window); "
                + "pausing automatic moves for \(cooldown) (\(stateDescription))"
        )
        cooldown = min(cooldown * 2, Self.maximumCooldown)
    }

    /// A user move is allowed through while open, and landing it closes the
    /// breaker. The escalated cooldown is kept for the next trip.
    func noteUserOverride() {
        let wasOpen = isOpen
        events.removeAll()
        openUntil = nil
        if wasOpen {
            MenuBarItemManager.diagLog.info(
                "Move circuit breaker cleared by a user move (\(stateDescription))"
            )
        }
    }

    private func prune(before now: ContinuousClock.Instant) {
        events.removeAll { now - $0.at > Self.window }
    }
}
