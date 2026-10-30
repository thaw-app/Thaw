//
//  TaskTimeoutTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Tasks with a timeout", .timeLimit(.minutes(1)))
struct TaskTimeoutTests {
    /// Matched by name: in the test build the thrown error and the app's TaskTimeoutError alias
    /// resolve to different types, so a type check fails on a real timeout.
    private static func isTimeout(_ error: any Error) -> Bool {
        String(describing: type(of: error)) == "TaskTimeoutError"
    }

    @Test("A task that finishes in time returns its value")
    func finishesInTime() async throws {
        let task = Task(timeout: .seconds(30), name: "fast") { 42 }
        #expect(try await task.value == 42)
    }

    @Test("A task that runs past its timeout throws the timeout error")
    func timesOut() async {
        let task = Task(timeout: .milliseconds(20)) {
            try await Task.sleep(for: .seconds(30))
            return 1
        }
        await #expect { try await task.value } throws: { Self.isTimeout($0) }
    }

    @Test("A detached task that finishes in time returns its value")
    func detachedFinishesInTime() async throws {
        let task = Task.detached(timeout: .seconds(30), name: "fast detached") { "done" }
        #expect(try await task.value == "done")
    }

    @Test("A detached task that runs past its timeout throws the timeout error")
    func detachedTimesOut() async {
        let task = Task.detached(timeout: .milliseconds(20)) {
            try await Task.sleep(for: .seconds(30))
            return 1
        }
        await #expect { try await task.value } throws: { Self.isTimeout($0) }
    }

    @Test("An operation's own error comes through unchanged")
    func operationErrorPassesThrough() async {
        struct Failure: Error {}
        let task = Task(timeout: .seconds(30)) { () throws -> Int in throw Failure() }
        await #expect(throws: Failure.self) { try await task.value }
    }
}
