//
//  SimpleSemaphoreTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Verifies `SimpleSemaphore.wait(timeout:)` reconciles a lost-race acquire
/// against a timeout: a permit won by `wait()` after the timeout has already
/// fired must be handed back, never leaked. See Plan 008.
///
/// The suite is `.serialized` because the race hammer drives 500 real
/// timeout-against-release races back to back and would otherwise starve the
/// rest of the parallel test plan. The time limit turns a reconciliation bug
/// that deadlocks the semaphore into a failure rather than a hung run.
@Suite("Simple semaphore timeout reconciliation", .serialized, .timeLimit(.minutes(1)))
struct SimpleSemaphoreTests {
    /// An uncontended wait acquires immediately; after signalling, a
    /// subsequent short-timeout wait also succeeds immediately.
    @Test("An uncontended wait, a signal, and a second wait all succeed")
    func uncontendedWaitThenSignalThenWaitAgain() async throws {
        let semaphore = SimpleSemaphore(value: 1)

        try await semaphore.wait(timeout: .milliseconds(50))
        await semaphore.signal()

        try await semaphore.wait(timeout: .milliseconds(50))
        await semaphore.signal()
    }

    /// A held semaphore causes a second waiter to time out; once the holder
    /// signals, a third waiter succeeds — no stranded state from the
    /// timeout.
    @Test("A timeout under contention leaves no stranded state behind")
    func timeoutUnderContentionLeavesNoStrandedState() async throws {
        let semaphore = SimpleSemaphore(value: 1)

        // Holder acquires the only permit.
        try await semaphore.wait(timeout: .milliseconds(50))

        // Second caller times out while the holder still owns the permit.
        await #expect(throws: SimpleSemaphore.TimeoutError.self) {
            try await semaphore.wait(timeout: .milliseconds(50))
        }

        // Holder releases.
        await semaphore.signal()

        // Third wait must succeed promptly; no permit or waiter is stranded.
        try await semaphore.wait(timeout: .milliseconds(500))
        await semaphore.signal()
    }

    /// Hammers the timeout/acquire race: a holder releases after a random
    /// 0-2 ms delay while a waiter times out at 1 ms. Whichever side wins
    /// reconciles and signals, so the semaphore never leaks or deadlocks.
    @Test("Every iteration of the timeout/acquire race reconciles")
    func raceHammerReconcilesEveryIteration() async throws {
        let semaphore = SimpleSemaphore(value: 1)
        // Start held so every iteration races the release against the
        // timeout.
        try await semaphore.wait(timeout: .milliseconds(50))

        for _ in 0..<500 {
            async let releaseTask: Void = {
                let delay = Duration.nanoseconds(Int.random(in: 0...2_000_000)) // 0-2 ms
                try? await Task.sleep(for: delay)
                await semaphore.signal()
            }()

            async let waitTask: Bool = {
                do {
                    try await semaphore.wait(timeout: .milliseconds(1))
                    return true
                } catch is SimpleSemaphore.TimeoutError {
                    return false
                } catch {
                    Issue.record("Unexpected error: \(error)")
                    return false
                }
            }()

            let acquired = await waitTask
            _ = await releaseTask

            if acquired {
                // The waiter won the race and now holds the permit that the
                // release() call restored; give it back for the next
                // iteration.
                await semaphore.signal()
            }
            // If the waiter timed out, reconciliation inside wait(timeout:)
            // already gave back any permit it might have raced into, and
            // release() already restored the held permit, so the semaphore
            // is back to "held by nobody, value == 1" either way.
        }

        // Final sanity check: the semaphore must be fully available.
        try await semaphore.wait(timeout: .seconds(1))
        await semaphore.signal()
    }

    /// A caller blocked in `wait(timeout:)` that is cancelled must observe
    /// `CancellationError`, not `TimeoutError`, and must leave the
    /// semaphore's state clean for the next waiter.
    @Test("Cancelling a blocked waiter throws CancellationError and leaves clean state")
    func cancellationDuringWaitThrowsCancellationErrorAndLeavesCleanState() async throws {
        let semaphore = SimpleSemaphore(value: 1)

        // Hold the only permit so the blocked task actually queues.
        try await semaphore.wait(timeout: .milliseconds(50))

        let blocked = Task {
            try await semaphore.wait(timeout: .seconds(5))
        }

        // Give the task a moment to start waiting, then cancel it.
        try await Task.sleep(for: .milliseconds(50))
        blocked.cancel()

        await #expect(throws: CancellationError.self) {
            try await blocked.value
        }

        // Release the held permit and confirm state is clean.
        await semaphore.signal()
        try await semaphore.wait(timeout: .milliseconds(500))
        await semaphore.signal()
    }
}
