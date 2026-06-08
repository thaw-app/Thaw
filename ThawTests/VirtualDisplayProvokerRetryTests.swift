//
//  VirtualDisplayProvokerRetryTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Tests for `ProvocationRetryState`, the pure-value struct that drives the
/// bounded retry / backoff logic inside `VirtualDisplayProvoker`.
///
/// Every test is free of `@MainActor`, live CG APIs, or `AppState` — the
/// struct holds only value-typed state (a dictionary and a `[TimeInterval]`).
/// The production default backoffs are `[120, 600]` (2 min / 10 min); tests
/// use shortened values (`[10, 30]`) to keep assertions readable and to prove
/// the logic is parametric.
final class VirtualDisplayProvokerRetryTests: XCTestCase {
    /// Anchor date used as "now" throughout the tests so results are
    /// deterministic regardless of the wall clock.
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - Fresh state

    /// A windowID with no recorded attempt is always eligible.
    func testFreshWindowIsEligibleForRetry() {
        let state = ProvocationRetryState(retryBackoffs: [10, 30])
        XCTAssertTrue(state.isEligibleForRetry(1, now: t0))
    }

    /// A windowID with no recorded attempt is not exhausted.
    func testFreshWindowIsNotExhausted() {
        let state = ProvocationRetryState(retryBackoffs: [10, 30])
        XCTAssertFalse(state.isExhausted(1))
    }

    /// `attempt(for:)` returns nil for a window with no recorded attempt.
    func testFreshWindowHasNoAttemptRecord() {
        let state = ProvocationRetryState(retryBackoffs: [10, 30])
        XCTAssertNil(state.attempt(for: 42))
    }

    // MARK: - After first failure

    /// After the first failed hold the window is in backoff: not eligible
    /// until `retryBackoffs[0]` seconds have elapsed.
    func testAfterFirstFailureWindowIsNotImmediatelyEligible() {
        var state = ProvocationRetryState(retryBackoffs: [10, 30])
        state.recordFailedAttempt(for: 1, now: t0)
        // Immediately after: not eligible.
        XCTAssertFalse(state.isEligibleForRetry(1, now: t0))
        // 1 s before the backoff ends: still not eligible.
        XCTAssertFalse(state.isEligibleForRetry(1, now: t0.addingTimeInterval(9)))
    }

    /// After `retryBackoffs[0]` seconds have elapsed the window becomes
    /// eligible again.
    func testAfterFirstBackoffWindowBecomesEligible() {
        var state = ProvocationRetryState(retryBackoffs: [10, 30])
        state.recordFailedAttempt(for: 1, now: t0)
        XCTAssertTrue(state.isEligibleForRetry(1, now: t0.addingTimeInterval(10)))
    }

    /// After the first failure the strike count is 1 and the window is not
    /// yet exhausted (exhaustion needs strikes > backoff count).
    func testAfterFirstFailureStrikeCountIsOneAndNotExhausted() {
        var state = ProvocationRetryState(retryBackoffs: [10, 30])
        state.recordFailedAttempt(for: 1, now: t0)
        XCTAssertEqual(state.attempt(for: 1)?.strikes, 1)
        XCTAssertFalse(state.isExhausted(1))
    }

    // MARK: - After second failure

    /// After the second failure the window enters the longer backoff and
    /// is still not exhausted (with 2 backoffs, exhaustion needs 3 strikes).
    func testAfterSecondFailureWindowIsInLongerBackoff() {
        var state = ProvocationRetryState(retryBackoffs: [10, 30])
        state.recordFailedAttempt(for: 1, now: t0)
        let t1 = t0.addingTimeInterval(10) // first backoff elapsed
        state.recordFailedAttempt(for: 1, now: t1)
        // Strike 2 sets retryAfter = t1 + 30.
        XCTAssertEqual(state.attempt(for: 1)?.strikes, 2)
        XCTAssertFalse(state.isExhausted(1))
        XCTAssertFalse(state.isEligibleForRetry(1, now: t1))
        XCTAssertFalse(state.isEligibleForRetry(1, now: t1.addingTimeInterval(29)))
        XCTAssertTrue(state.isEligibleForRetry(1, now: t1.addingTimeInterval(30)))
    }

    // MARK: - Exhaustion

    /// Once strikes exceed `retryBackoffs.count` the window is exhausted
    /// and `isEligibleForRetry` always returns false.
    func testAfterAllBackoffsExhaustedWindowIsNeverEligible() {
        var state = ProvocationRetryState(retryBackoffs: [10, 30])
        state.recordFailedAttempt(for: 1, now: t0)                           // strike 1
        state.recordFailedAttempt(for: 1, now: t0.addingTimeInterval(10))    // strike 2
        state.recordFailedAttempt(for: 1, now: t0.addingTimeInterval(40))    // strike 3 → exhausted

        XCTAssertTrue(state.isExhausted(1))
        // distantFuture is used as retryAfter once exhausted.
        XCTAssertFalse(state.isEligibleForRetry(1, now: .distantFuture))
    }

    /// Exhausted windows have a strike count one beyond the backoff count.
    func testExhaustedWindowStrikeCountExceedsBackoffCount() {
        var state = ProvocationRetryState(retryBackoffs: [10, 30])
        state.recordFailedAttempt(for: 1, now: t0)
        state.recordFailedAttempt(for: 1, now: t0.addingTimeInterval(10))
        state.recordFailedAttempt(for: 1, now: t0.addingTimeInterval(40))
        XCTAssertEqual(state.attempt(for: 1)?.strikes, 3) // 3 > 2 (backoff count)
    }

    // MARK: - Multiple independent windows

    /// Each windowID tracks its state independently; a failure for window A
    /// must not affect window B.
    func testMultipleWindowsTrackIndependently() {
        var state = ProvocationRetryState(retryBackoffs: [10, 30])
        state.recordFailedAttempt(for: 1, now: t0)
        // Window 2 has never been attempted: always eligible.
        XCTAssertTrue(state.isEligibleForRetry(2, now: t0))
        // Window 1 is in backoff.
        XCTAssertFalse(state.isEligibleForRetry(1, now: t0))
    }

    // MARK: - Prune stale entries

    /// Entries for windowIDs no longer in the orphan set are removed;
    /// entries for still-active orphans are kept.
    func testPruneStaleEntriesRemovesStaleWindowIDs() {
        var state = ProvocationRetryState(retryBackoffs: [10, 30])
        state.recordFailedAttempt(for: 1, now: t0)
        state.recordFailedAttempt(for: 2, now: t0)
        state.pruneStaleEntries(keepingOnly: [2])
        XCTAssertNil(state.attempt(for: 1), "stale entry should have been removed")
        XCTAssertNotNil(state.attempt(for: 2), "active entry should remain")
    }

    /// Pruning with an empty orphan set removes all entries.
    func testPruneWithEmptySetClearsAllEntries() {
        var state = ProvocationRetryState(retryBackoffs: [10, 30])
        state.recordFailedAttempt(for: 1, now: t0)
        state.recordFailedAttempt(for: 2, now: t0)
        state.pruneStaleEntries(keepingOnly: [])
        XCTAssertNil(state.attempt(for: 1))
        XCTAssertNil(state.attempt(for: 2))
    }

    // MARK: - Production backoff values

    /// Smoke-test with the production backoffs (`[120, 600]`) to verify
    /// the default initialiser wires them correctly.
    func testProductionBackoffsWiredCorrectly() {
        var state = ProvocationRetryState() // default: [120, 600]
        state.recordFailedAttempt(for: 99, now: t0)
        XCTAssertEqual(state.retryBackoffs, [120, 600])
        // In backoff until t0 + 120.
        XCTAssertFalse(state.isEligibleForRetry(99, now: t0.addingTimeInterval(119)))
        XCTAssertTrue(state.isEligibleForRetry(99, now: t0.addingTimeInterval(120)))
    }
}
