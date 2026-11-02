//
//  WithAbandoningTimeout.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// An error that indicates a task timed out before completion.
public struct TaskTimeoutError: CustomStringConvertible, LocalizedError, Sendable {
    public let description = "Task timed out before completion"

    public var errorDescription: String? {
        description
    }

    public init() {}
}

/// Races operation against timeout, abandoning, not awaiting, the
/// operation when the deadline wins.
///
/// A task-group race waits for every child, so an operation that ignores
/// cancellation (a lost XPC reply, a hung framework call) would hold the
/// caller forever. Here the operation runs unstructured and a late result is
/// discarded; exactly one of deadline, operation and caller cancellation
/// resumes the continuation, so it never double-resumes.
///
/// The deadline is cancelled as soon as the caller resumes, or every call
/// would leave a pointless timer wakeup, which adds up at capture-refresh rates.
public func withAbandoningTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let oneShot = OneShotContinuation<T, any Error>()
    let deadline = Task.detached {
        do {
            try await Task.sleep(for: timeout)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        oneShot.settle(.failure(TaskTimeoutError()))
    }
    defer { deadline.cancel() }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            oneShot.setContinuation(continuation)
            Task.detached {
                do {
                    let value = try await operation()
                    oneShot.settle(.success(value))
                } catch {
                    oneShot.settle(.failure(error))
                }
            }
        }
    } onCancel: {
        oneShot.settle(.failure(CancellationError()))
    }
}
