//
//  ThawConcurrencyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawConcurrency

@Suite("One-shot continuation")
struct OneShotContinuationTests {
    @Test func settleBeforeRegisterDeliversStoredValue() async throws {
        let oneShot = OneShotContinuation<Int, any Error>()
        oneShot.settle(.success(7))
        let value = try await withCheckedThrowingContinuation { continuation in
            oneShot.setContinuation(continuation)
        }
        #expect(value == 7)
    }

    @Test func settleBeforeRegisterDeliversStoredError() async {
        let oneShot = OneShotContinuation<Int, any Error>()
        oneShot.settle(.failure(CancellationError()))
        await #expect(throws: CancellationError.self) {
            try await withCheckedThrowingContinuation { continuation in
                oneShot.setContinuation(continuation)
            }
        }
    }

    @Test func onlyTheFirstSettleResumesTheCaller() async throws {
        let oneShot = OneShotContinuation<Int, any Error>()
        oneShot.settle(.success(1))
        // The second settle must be ignored; resuming twice would crash.
        oneShot.settle(.failure(CancellationError()))
        let value = try await withCheckedThrowingContinuation { continuation in
            oneShot.setContinuation(continuation)
        }
        #expect(value == 1)
    }
}

@Suite("Abandoning timeout")
struct AbandoningTimeoutTests {
    @Test func valueBeforeTimeoutIsReturned() async throws {
        let value = try await withAbandoningTimeout(.seconds(5)) {
            try await Task.sleep(for: .milliseconds(10))
            return 42
        }
        #expect(value == 42)
    }

    @Test func deadlineThrowsTimeout() async throws {
        await #expect(throws: TaskTimeoutError.self) {
            try await withAbandoningTimeout(.milliseconds(100)) {
                try await Task.sleep(for: .seconds(30))
                return true
            }
        }
    }

    @Test func alreadyCancelledCallerDoesNotWaitOutDeadline() async throws {
        let start = ContinuousClock.now
        let task = Task { () -> Int in
            // Cancellation arrives before the timeout handler is installed,
            // which is the window the one-shot continuation must not lose.
            withUnsafeCurrentTask { $0?.cancel() }
            return try await withAbandoningTimeout(.seconds(5)) {
                try await Task.sleep(for: .seconds(5))
                return 1
            }
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(ContinuousClock.now - start < .seconds(2))
    }
}
