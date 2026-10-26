//
//  RecordedSleeps.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Synchronization

/// Stands in for Task.sleep so a test runs without real time.
///
/// Each wait is recorded and returns at once, without suspending, and throws
/// when the task was cancelled, as Task.sleep would. A test awaits a number of
/// waits instead of a deadline. Since the wait never suspends, code on the main
/// actor runs on to its next suspension before an awaiting test resumes.
final class RecordedSleeps: Sendable {
    private struct Waiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var durations: [Duration] = []
        var waiters: [Waiter] = []
    }

    private let state = Mutex(State())

    /// Every wait asked for, oldest first.
    var durations: [Duration] {
        state.withLock { $0.durations }
    }

    /// Records the wait and returns at once, throwing when the task was cancelled.
    func sleep(for duration: Duration) throws {
        let ready = state.withLock { state in
            state.durations.append(duration)
            let count = state.durations.count
            let ready = state.waiters.filter { $0.count <= count }
            state.waiters.removeAll { $0.count <= count }
            return ready
        }
        for waiter in ready {
            waiter.continuation.resume()
        }
        try Task.checkCancellation()
    }

    /// Returns once this many waits have been asked for in all.
    func waitForSleeps(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let reached = state.withLock { state in
                guard state.durations.count < count else { return true }
                state.waiters.append(Waiter(count: count, continuation: continuation))
                return false
            }
            if reached {
                continuation.resume()
            }
        }
    }
}
