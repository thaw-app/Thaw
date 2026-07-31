//
//  ConcurrencyHelpersTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import os.lock
import Testing
@testable import Thaw

/// Covers the `Task` timeout helpers: `withTimeout`, the `Task(timeout:)`
/// initializer, and `Task.detached(timeout:)`.
///
/// Every case races a real sleep against a real budget, so the two sides are
/// kept an order of magnitude apart — a 50 ms budget against a 5 s operation,
/// or a 5 s budget against work that returns immediately. Nothing here
/// asserts on elapsed wall-clock time, only on which side won.
@Suite("Task timeout helpers")
struct ConcurrencyHelpersTests {
    /// Comfortably longer than any operation that is meant to finish.
    private static let generousBudget: Duration = .seconds(5)
    /// Comfortably shorter than any operation that is meant to be cut off.
    private static let tightBudget: Duration = .milliseconds(50)

    // MARK: withTimeout

    @Test("An operation that finishes inside the budget returns its value")
    func fastOperationReturnsItsValue() async throws {
        let result = try await Task<String, any Error>.withTimeout(Self.generousBudget) {
            "done"
        }

        #expect(result == "done")
    }

    @Test("An operation that overruns the budget throws TaskTimeoutError")
    func slowOperationTimesOut() async {
        await #expect(throws: TaskTimeoutError.self) {
            try await Task<String, any Error>.withTimeout(Self.tightBudget) {
                try await Task.sleep(for: .seconds(5))
                return "never"
            }
        }
    }

    @Test("The operation's own error propagates instead of the timeout")
    func operationErrorPropagates() async {
        struct Boom: Error {}

        await #expect(throws: Boom.self) {
            try await Task<String, any Error>.withTimeout(Self.generousBudget) {
                throw Boom()
            }
        }
    }

    @Test("A timed-out operation is cancelled, not left running")
    func timedOutOperationIsCancelled() async throws {
        let observed = OSAllocatedUnfairLock(initialState: false)

        await #expect(throws: TaskTimeoutError.self) {
            try await Task<String, any Error>.withTimeout(Self.tightBudget) {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    // The group cancels the losing arm, which surfaces here.
                    observed.withLock { $0 = true }
                    throw error
                }
                return "never"
            }
        }

        // The cancellation is delivered after withTimeout has already thrown,
        // so poll until the losing arm observes it — a fixed sleep would race
        // scheduler latency. The deadline keeps a regression from hanging.
        let deadline = ContinuousClock.now + .seconds(5)
        while !observed.withLock({ $0 }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.withLock { $0 })
    }

    @Test("A custom clock and tolerance are accepted")
    func acceptsACustomClock() async throws {
        let result = try await Task<Int, any Error>.withTimeout(
            .seconds(5),
            tolerance: .milliseconds(10),
            clock: SuspendingClock()
        ) {
            42
        }

        #expect(result == 42)
    }

    // MARK: Task(timeout:)

    @Test("Task(timeout:) yields the value when the operation is fast")
    func unstructuredTaskReturnsItsValue() async throws {
        let task = Task(timeout: Self.generousBudget) {
            "done"
        }

        #expect(try await task.value == "done")
    }

    @Test("Task(timeout:) fails with TaskTimeoutError when the operation drags")
    func unstructuredTaskTimesOut() async {
        let task = Task(timeout: Self.tightBudget) {
            try await Task.sleep(for: .seconds(5))
            return "never"
        }

        await #expect(throws: TaskTimeoutError.self) {
            try await task.value
        }
    }

    // MARK: Task.detached(timeout:)

    @Test("Task.detached(timeout:) yields the value when the operation is fast")
    func detachedTaskReturnsItsValue() async throws {
        let task = Task.detached(timeout: Self.generousBudget) {
            "done"
        }

        #expect(try await task.value == "done")
    }

    @Test("Task.detached(timeout:) fails with TaskTimeoutError when the operation drags")
    func detachedTaskTimesOut() async {
        let task = Task.detached(timeout: Self.tightBudget) {
            try await Task.sleep(for: .seconds(5))
            return "never"
        }

        await #expect(throws: TaskTimeoutError.self) {
            try await task.value
        }
    }

    // MARK: TaskTimeoutError

    @Test("The timeout error describes itself for both Error surfaces")
    func timeoutErrorIsDescribed() {
        let error = TaskTimeoutError()

        #expect(!error.description.isEmpty)
        #expect(error.errorDescription == error.description)
        #expect(error.localizedDescription == error.description)
    }
}
