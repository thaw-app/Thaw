//
//  ConcurrencyHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Foundation
import os.lock

// MARK: - Debounced Notification Task

/// Starts a `MainActor` task that owns a notification observer feeding a
/// debounced `AsyncChannel`: bursts of notifications posted to `center`
/// coalesce over `interval`, then `action` runs once per burst.
///
/// The observer is registered before this returns — no notification can
/// slip past during task startup — and is removed by the task's defer
/// when it ends, so the non-Sendable observer token stays confined to
/// this MainActor context. Cancel the returned task to stop observing;
/// a repeated setup must cancel the previous task before starting a new
/// one, or the old observer keeps yielding into its own stream.
@MainActor
func debouncedNotificationTask(
    center: NotificationCenter,
    name: Notification.Name,
    interval: Duration,
    action: @escaping @MainActor () async -> Void
) -> Task<Void, Never> {
    let events = AsyncChannel<Void>()
    let observer = center.addObserver(
        forName: name,
        object: nil,
        queue: .main
    ) { _ in Task { await events.send(()) } }
    return Task { @MainActor in
        defer { center.removeObserver(observer) }
        for await _ in events.debounce(for: interval) {
            await action()
        }
    }
}

// MARK: - Task Timeout

/// An error that indicates that a task timed out.
struct TaskTimeoutError: CustomStringConvertible, LocalizedError {
    let description = "Task timed out before completion"
    var errorDescription: String? {
        description
    }
}

nonisolated extension Task {
    static func withTimeout<C: Clock>(
        _ timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = .continuous,
        operation: @escaping @Sendable () async throws -> Success
    ) async throws -> Success {
        try await withThrowingTaskGroup(of: Success.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await _Concurrency.Task.sleep(for: timeout, tolerance: tolerance, clock: clock)
                throw TaskTimeoutError()
            }
            guard let success = try await group.next() else {
                throw _Concurrency.CancellationError()
            }
            group.cancelAll()
            return success
        }
    }
}

nonisolated extension Task where Failure == any Error {
    /// Runs the given throwing operation asynchronously as part of a
    /// new _unstructured_ top-level task.
    ///
    /// If the operation does not complete within the provided duration,
    /// the task is cancelled and a ``TaskTimeoutError`` is thrown.
    ///
    /// - Parameters:
    ///   - timeout: The duration the operation must complete within.
    ///   - tolerance: The precision threshold of the timeout operation.
    ///   - clock: The clock that manages the timeout operation.
    ///   - name: Human readable name of the task.
    ///   - priority: The priority of the operation.
    ///   - operation: The operation to perform.
    @discardableResult
    init<C: Clock>(
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = .continuous,
        name: String? = nil,
        priority: TaskPriority? = nil,
        @_inheritActorContext @_implicitSelfCapture
        operation: @escaping @Sendable () async throws -> Success
    ) {
        self.init(name: name, priority: priority) {
            try await Task.withTimeout(timeout, tolerance: tolerance, clock: clock, operation: operation)
        }
    }

    /// Runs the given throwing operation asynchronously as part of a
    /// new _unstructured_ _detached_ top-level task.
    ///
    /// If the operation does not complete within the provided duration,
    /// the task is cancelled and a ``TaskTimeoutError`` is thrown.
    ///
    /// - Parameters:
    ///   - timeout: The duration the operation must complete within.
    ///   - tolerance: The precision threshold of the timeout operation.
    ///   - clock: The clock that manages the timeout operation.
    ///   - name: Human readable name of the task.
    ///   - priority: The priority of the operation.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: A reference to the task.
    @discardableResult
    static func detached<C: Clock>(
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = .continuous,
        name: String? = nil,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Success
    ) -> Task<Success, Failure> {
        detached(name: name, priority: priority) {
            try await withTimeout(timeout, tolerance: tolerance, clock: clock, operation: operation)
        }
    }
}
