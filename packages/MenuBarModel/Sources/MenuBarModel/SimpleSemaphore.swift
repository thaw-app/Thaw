//
//  SimpleSemaphore.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Simple actor-based semaphore to prevent overlapping operations
public actor SimpleSemaphore {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var value: Int
    private var waiters: [Waiter] = [] // FIFO

    public init(value: Int) {
        precondition(value >= 0, "SimpleSemaphore requires a non-negative value")
        self.value = value
    }

    /// Holds one permit through every suspension in an operation, including
    /// its final commit. Cancellation while queued never enters the operation.
    public func withPermit<Result: Sendable>(
        isolation _: isolated (any Actor)? = #isolation,
        _ operation: () async throws -> Result
    ) async throws -> Result {
        try await wait()
        do {
            try Task.checkCancellation()
            let result = try await operation()
            await signal()
            return result
        } catch {
            await signal()
            throw error
        }
    }

    /// Waits for, or decrements, the semaphore, throwing on cancellation.
    public func wait() async throws {
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
    public struct TimeoutError: Error {}

    /// Waits for, or decrements, the semaphore with a timeout.
    /// Throws CancellationError on cancellation or
    /// TimeoutError on timeout.
    public func wait(timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await self.wait()
                return true
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return false
            }

            defer { group.cancelAll() }

            // The first task to finish wins: true means the permit was
            // acquired, false means the timeout fired.
            let first = try await group.next()
            guard first != true else {
                return
            }

            group.cancelAll()

            // The timeout won. The wait task may have been granted a permit in
            // the same instant, before cancellation could remove its waiter;
            // drain and release any acquired permit so it is not leaked.
            while let acquired = try? await group.next() {
                if acquired {
                    signal()
                }
            }
            throw TimeoutError()
        }
    }

    /// Signals the semaphore, resuming the next waiter if present.
    ///
    /// Always increment value, then wake a queued waiter only when the
    /// post-increment value is still non-positive. Skipping the increment
    /// when waking a waiter would let value drift negative under contention,
    /// leaving later callers suspended forever in wait.
    public func signal() {
        value += 1
        if value <= 0, let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume(returning: ())
        }
    }

    /// Resets the semaphore to a given value, cancelling all pending waiters.
    /// Use only as a last resort when the semaphore is suspected to be leaked.
    ///
    /// This is not a timeout recovery: a timeout means another operation is
    /// still holding the permit legitimately, and resetting would cancel that
    /// holder's queued work and let a second operation run concurrently.
    public func reset(to value: Int = 1) {
        for waiter in waiters {
            waiter.continuation.resume(throwing: CancellationError())
        }
        waiters.removeAll()
        self.value = value
    }
}
