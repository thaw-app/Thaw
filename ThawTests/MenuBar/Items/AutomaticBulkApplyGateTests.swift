//
//  AutomaticBulkApplyGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the gate that rations automatic bulk applies once batches
/// stop completing.
///
/// On a bar that refuses synthetic drags, the divergence re-dispatches every
/// unfinished apply in a loop that hides the cursor each pass (#899, #900).
/// A failed batch gets one retry, then one attempt per cooldown.
@Suite("Automatic bulk apply gate")
struct AutomaticBulkApplyGateTests {
    private let clock = ContinuousClock()

    /// The ordinary case: no failure history, nothing to ration.
    @Test("A clean history permits dispatch")
    func cleanHistoryPermits() {
        #expect(
            MoveCircuitBreaker.bulkApplyPermitted(
                consecutiveUnfinishedBatches: 0,
                lastUnfinishedBatchAt: nil,
                now: clock.now
            )
        )
    }

    /// One unfinished batch earns a retry.
    @Test("A single unfinished batch permits the retry")
    func singleFailurePermitsRetry() {
        #expect(
            MoveCircuitBreaker.bulkApplyPermitted(
                consecutiveUnfinishedBatches: 1,
                lastUnfinishedBatchAt: clock.now,
                now: clock.now
            )
        )
    }

    /// Two in a row is the signature of a bar that refuses the moves.
    @Test("A second consecutive unfinished batch blocks immediate dispatch")
    func secondFailureBlocksImmediateDispatch() {
        let now = clock.now
        #expect(
            !MoveCircuitBreaker.bulkApplyPermitted(
                consecutiveUnfinishedBatches: 2,
                lastUnfinishedBatchAt: now,
                now: now
            )
        )
    }

    /// Rationed, not stopped: after the cooldown the bar gets another chance.
    @Test("An exhausted streak dispatches again after the cooldown")
    func cooldownRestoresDispatch() {
        let failedAt = clock.now
        #expect(
            MoveCircuitBreaker.bulkApplyPermitted(
                consecutiveUnfinishedBatches: 2,
                lastUnfinishedBatchAt: failedAt,
                now: failedAt.advanced(by: .seconds(60)),
                cooldown: .seconds(60)
            )
        )
    }

    /// Inside the cooldown the streak keeps blocking, however long it is.
    @Test("A streak inside the cooldown stays blocked")
    func streakInsideCooldownBlocks() {
        let failedAt = clock.now
        #expect(
            !MoveCircuitBreaker.bulkApplyPermitted(
                consecutiveUnfinishedBatches: 5,
                lastUnfinishedBatchAt: failedAt,
                now: failedAt.advanced(by: .seconds(59)),
                cooldown: .seconds(60)
            )
        )
    }

    /// A streak with no timestamp cannot be aged, so it must not block forever.
    /// Unreachable in practice, but the answer should still be permissive.
    @Test("A streak without a timestamp permits dispatch")
    func streakWithoutTimestampPermits() {
        #expect(
            MoveCircuitBreaker.bulkApplyPermitted(
                consecutiveUnfinishedBatches: 3,
                lastUnfinishedBatchAt: nil,
                now: clock.now
            )
        )
    }

    /// After the hard cap the gate stops dispatching, even past the cooldown.
    /// Otherwise a bar that refuses drags re-fires a cursor-hijacking batch
    /// every 60 s. Only a successful batch clears the cap.
    @Test("The hard cap blocks dispatch permanently, even after the cooldown")
    func hardCapBlocksAfterCooldown() {
        let failedAt = clock.now
        let wayPast = failedAt.advanced(by: .seconds(3600))
        #expect(
            !MoveCircuitBreaker.bulkApplyPermitted(
                consecutiveUnfinishedBatches: 6,
                lastUnfinishedBatchAt: failedAt,
                now: wayPast,
                cooldown: .seconds(60)
            )
        )
    }

    @Test("Below the hard cap the cooldown still allows a retry")
    func belowHardCapCooldownAllowsRetry() {
        let failedAt = clock.now
        #expect(
            MoveCircuitBreaker.bulkApplyPermitted(
                consecutiveUnfinishedBatches: 5,
                lastUnfinishedBatchAt: failedAt,
                now: failedAt.advanced(by: .seconds(60)),
                cooldown: .seconds(60)
            )
        )
    }
}

/// Characterizes the idle window an automatic bulk apply waits for before
/// it starts issuing moves.
///
/// A batch hides the cursor for its whole length, so dispatching mid-interaction
/// takes the pointer away (#899, #723). The gate waits for a lull and defers
/// if the deadline expires while input is still active.
@Suite("Bulk apply idle gate")
struct BulkApplyIdleGateTests {
    /// Off by default. A non-positive threshold skips the wait loop entirely.
    @Test("A non-positive threshold disables the gate", arguments: [0, -1, -250])
    func nonPositiveThresholdDisables(thresholdMs: Int) {
        #expect(
            MenuBarItemManager.bulkApplyIdleWindow(thresholdMs: thresholdMs, capMs: 2000) == nil
        )
    }

    /// A configured threshold produces the window the wait loop polls on.
    @Test("A positive threshold produces a window")
    func positiveThresholdProducesWindow() {
        let window = MenuBarItemManager.bulkApplyIdleWindow(thresholdMs: 250, capMs: 2000)
        #expect(window?.threshold == .milliseconds(250))
        #expect(window?.cap == .milliseconds(2000))
    }

    /// A negative cap from a defaults typo must mean "don't wait", not "never start".
    @Test("A negative cap clamps to zero rather than blocking forever")
    func negativeCapClamps() {
        let window = MenuBarItemManager.bulkApplyIdleWindow(thresholdMs: 250, capMs: -1)
        #expect(window?.cap == .zero)
    }

    /// An idle bar passes the first poll.
    @Test("A paused user concludes the wait immediately")
    func pausedUserConcludesImmediately() {
        #expect(
            MenuBarItemManager.bulkApplyIdleWaitDecision(
                userHasPausedInput: true,
                elapsed: .zero,
                cap: .milliseconds(2000)
            ) == .ready
        )
    }

    /// Input still in flight and time on the clock: keep waiting.
    @Test("An active user inside the cap keeps waiting")
    func activeUserInsideCapWaits() {
        #expect(
            MenuBarItemManager.bulkApplyIdleWaitDecision(
                userHasPausedInput: false,
                elapsed: .milliseconds(500),
                cap: .milliseconds(2000)
            ) == .waiting
        )
    }

    /// The deadline defers automatic work instead of authorizing a move over
    /// continuing input.
    @Test("The deadline defers while input remains active")
    func deadlineDefersActiveInput() {
        #expect(
            MenuBarItemManager.bulkApplyIdleWaitDecision(
                userHasPausedInput: false,
                elapsed: .milliseconds(2000),
                cap: .milliseconds(2000)
            ) == .deferBatch
        )
    }

    /// A clamped zero deadline immediately defers active-input work.
    @Test("A zero deadline immediately defers active input")
    func zeroDeadlineDefers() {
        #expect(
            MenuBarItemManager.bulkApplyIdleWaitDecision(
                userHasPausedInput: false,
                elapsed: .zero,
                cap: .zero
            ) == .deferBatch
        )
    }

    @Test("Only automatic batches yield when physical input resumes")
    func automaticBatchYieldsBetweenMoves() {
        #expect(MenuBarItemManager.automaticBatchShouldYieldForInput(
            automatic: true,
            userHasPausedPhysicalInput: false
        ))
        #expect(!MenuBarItemManager.automaticBatchShouldYieldForInput(
            automatic: false,
            userHasPausedPhysicalInput: false
        ))
        #expect(!MenuBarItemManager.automaticBatchShouldYieldForInput(
            automatic: true,
            userHasPausedPhysicalInput: true
        ))
    }
}

/// Characterizes the circuit breaker that abandons a move batch after a
/// run of consecutive failures.
///
/// The cursor stays hidden for the whole batch and each failing move burns its
/// full attempt budget (#899). Three in a row means the rest will fail too.
@Suite("Move batch circuit breaker")
struct MoveBatchCircuitBreakerTests {
    /// A batch with no failures runs to completion.
    @Test("No failures does not abandon")
    func noFailuresDoesNotAbandon() {
        #expect(!MoveCircuitBreaker.batchShouldAbandon(consecutiveFailures: 0))
    }

    /// Failures below the threshold, or reset by a success, keep the batch going.
    @Test("Failures below the threshold do not abandon", arguments: [1, 2])
    func belowThresholdDoesNotAbandon(count: Int) {
        #expect(!MoveCircuitBreaker.batchShouldAbandon(consecutiveFailures: count))
    }

    /// The third consecutive failure trips the breaker.
    @Test("The threshold abandons the batch")
    func thresholdAbandons() {
        #expect(MoveCircuitBreaker.batchShouldAbandon(consecutiveFailures: 3))
    }
}
