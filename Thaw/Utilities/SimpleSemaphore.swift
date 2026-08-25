//
//  SimpleSemaphore.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Collections
import Foundation

/// Simple actor-based semaphore to prevent overlapping operations
actor SimpleSemaphore {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var value: Int
    private var waiters: Deque<Waiter> = [] // FIFO; O(1) popFirst instead of Array's O(n) removeFirst

    init(value: Int) {
        precondition(value >= 0, "SimpleSemaphore requires a non-negative value")
        self.value = value
    }

    /// Waits for, or decrements, the semaphore, throwing on cancellation.
    func wait() async throws {
        if Task.isCancelled {
            throw CancellationError()
        }

        value -= 1
        if value >= 0 {
            return
        }

        let id = UUID()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: { [weak self] in
            Task.detached { await self?.cancelWaiter(withID: id) }
        }
    }

    private func cancelWaiter(withID id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            // The waiter was already consumed by signal(); don't touch the value.
            return
        }
        value += 1
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    /// An error that indicates the semaphore wait timed out.
    struct TimeoutError: Error {}

    private enum WaitOutcome {
        case acquired
        case timedOut
    }

    /// Waits for, or decrements, the semaphore with a timeout.
    /// Throws ``CancellationError`` on cancellation or
    /// ``TimeoutError`` on timeout.
    ///
    /// Invariant 1: on `TimeoutError`, the semaphore's state is exactly as
    /// if this call never happened (no permit held, no waiter left behind).
    /// Invariant 2: on normal return, exactly one permit is held.
    func wait(timeout: Duration) async throws {
        let outcome: WaitOutcome = try await withThrowingTaskGroup(of: WaitOutcome.self) { group in
            group.addTask {
                try await self.wait()
                return .acquired
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return .timedOut
            }
            // The first child to finish wins. The group always has exactly
            // two children at this point, so next() must return a value.
            guard let first = try await group.next() else {
                preconditionFailure("SimpleSemaphore.wait: task group unexpectedly empty")
            }
            group.cancelAll()
            if first == .timedOut {
                // The acquire child may STILL have won the race against
                // cancellation (it may have decremented `value` before
                // cancelAll() landed). Drain it: an .acquired result means
                // we hold a permit nobody will use, so give it back to
                // preserve invariant 1. A CancellationError from the drain
                // is the normal case (the acquire child was cancelled
                // cleanly before winning) and is swallowed.
                do {
                    while let drained = try await group.next() {
                        if drained == .acquired {
                            self.signal()
                        }
                    }
                } catch is CancellationError {
                    // Acquire child cancelled cleanly — nothing held.
                }
            } else {
                // Acquired. Drain the cancelled timeout-sleep child and
                // ignore its error (CancellationError); this preserves
                // invariant 2.
                while await (try? group.next()) != nil {
                    // Intentionally empty: draining the cancelled child, result discarded.
                }
            }
            return first
        }
        if outcome == .timedOut {
            throw TimeoutError()
        }
    }

    /// Signals the semaphore, resuming the next waiter if present.
    ///
    /// Standard counting-semaphore semantics: always increment value,
    /// then wake a queued waiter only when the post-increment value is
    /// still non-positive (meaning waiters remain). The previous
    /// implementation skipped the increment when waking a waiter, which
    /// caused value to drift negative when concurrent callers queued
    /// up during a long-running holder; every subsequent caller would
    /// then see value < 0 in wait and suspend forever even after all
    /// prior holders had released.
    func signal() {
        value += 1
        if value <= 0, let waiter = waiters.popFirst() {
            waiter.continuation.resume(returning: ())
        }
    }

    /// Resets the semaphore to a given value, cancelling all pending waiters.
    /// Use ONLY as a last resort when the semaphore is suspected to be leaked.
    func reset(to value: Int = 1) {
        for waiter in waiters {
            waiter.continuation.resume(throwing: CancellationError())
        }
        waiters.removeAll()
        self.value = value
    }
}
