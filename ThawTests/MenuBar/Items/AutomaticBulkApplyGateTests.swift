//
//  AutomaticBulkApplyGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the gate that rations automatic bulk applies once batches
/// stop completing.
///
/// On a bar that refuses synthetic drags, every apply ends unfinished, the
/// save withhold keeps the divergence alive, and the divergence re-dispatches
/// the next apply — an unbounded loop in which the cursor is hidden for the
/// length of a batch on every pass (#899, #900). The gate allows a failed
/// batch one retry, then rations further attempts to one per cooldown.
@Suite("Automatic bulk apply gate")
struct AutomaticBulkApplyGateTests {
    private let clock = ContinuousClock()

    /// The ordinary case: no failure history, nothing to ration.
    @Test("A clean history permits dispatch")
    func cleanHistoryPermits() {
        #expect(
            MenuBarItemManager.automaticBulkApplyPermitted(
                consecutiveUnfinishedBatches: 0,
                lastUnfinishedBatchAt: nil,
                now: clock.now
            )
        )
    }

    /// One unfinished batch earns the retry the save-withhold window
    /// exists to make room for.
    @Test("A single unfinished batch permits the retry")
    func singleFailurePermitsRetry() {
        #expect(
            MenuBarItemManager.automaticBulkApplyPermitted(
                consecutiveUnfinishedBatches: 1,
                lastUnfinishedBatchAt: clock.now,
                now: clock.now
            )
        )
    }

    /// Two in a row is the signature of a bar that refuses the moves; the
    /// pass that would have dispatched immediately afterwards is the one
    /// the loop is made of.
    @Test("A second consecutive unfinished batch blocks immediate dispatch")
    func secondFailureBlocksImmediateDispatch() {
        let now = clock.now
        #expect(
            !MenuBarItemManager.automaticBulkApplyPermitted(
                consecutiveUnfinishedBatches: 2,
                lastUnfinishedBatchAt: now,
                now: now
            )
        )
    }

    /// Rationed, not stopped: once the cooldown has passed, the bar gets
    /// another chance in case whatever refused the drags has cleared.
    @Test("An exhausted streak dispatches again after the cooldown")
    func cooldownRestoresDispatch() {
        let failedAt = clock.now
        #expect(
            MenuBarItemManager.automaticBulkApplyPermitted(
                consecutiveUnfinishedBatches: 2,
                lastUnfinishedBatchAt: failedAt,
                now: failedAt.advanced(by: .seconds(60)),
                cooldown: .seconds(60)
            )
        )
    }

    /// Inside the cooldown the streak keeps blocking, however long it is.
    @Test("A long streak inside the cooldown stays blocked")
    func longStreakInsideCooldownBlocks() {
        let failedAt = clock.now
        #expect(
            !MenuBarItemManager.automaticBulkApplyPermitted(
                consecutiveUnfinishedBatches: 7,
                lastUnfinishedBatchAt: failedAt,
                now: failedAt.advanced(by: .seconds(59)),
                cooldown: .seconds(60)
            )
        )
    }

    /// A streak with no timestamp cannot be aged, so it must not block
    /// forever; the timestamp is cleared by the same clean batch that
    /// resets the streak, making this pairing unreachable in practice —
    /// but the gate's answer for it should still be the permissive one.
    @Test("A streak without a timestamp permits dispatch")
    func streakWithoutTimestampPermits() {
        #expect(
            MenuBarItemManager.automaticBulkApplyPermitted(
                consecutiveUnfinishedBatches: 3,
                lastUnfinishedBatchAt: nil,
                now: clock.now
            )
        )
    }
}

/// Characterizes the circuit breaker that abandons a move batch after a
/// run of consecutive failures.
///
/// The cursor stays hidden for the whole batch, and each failing move burns
/// its full attempt budget before throwing; one #900 pass logged 15 such
/// failures back to back (#899). Three in a row with no success between
/// them is enough evidence that the items still queued will fare no better.
@Suite("Move batch circuit breaker")
struct MoveBatchCircuitBreakerTests {
    /// A batch with no failures runs to completion.
    @Test("No failures does not abandon")
    func noFailuresDoesNotAbandon() {
        #expect(!MenuBarItemManager.moveBatchShouldAbandon(consecutiveFailures: 0))
    }

    /// Scattered failures below the threshold — including the two that a
    /// success later resets — keep the batch going.
    @Test("Failures below the threshold do not abandon", arguments: [1, 2])
    func belowThresholdDoesNotAbandon(count: Int) {
        #expect(!MenuBarItemManager.moveBatchShouldAbandon(consecutiveFailures: count))
    }

    /// The third consecutive failure trips the breaker.
    @Test("The threshold abandons the batch")
    func thresholdAbandons() {
        #expect(MenuBarItemManager.moveBatchShouldAbandon(consecutiveFailures: 3))
    }
}
