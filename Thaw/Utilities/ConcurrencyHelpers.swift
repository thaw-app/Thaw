//
//  ConcurrencyHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Foundation
import Observation
import os.lock

// MARK: - Debounced Notification Task

/// Starts a `MainActor` task that feeds `center` notifications into a debounced
/// `AsyncChannel` and runs `action` once per burst coalesced over `interval`.
///
/// The observer is registered before this returns and removed when the task
/// ends. Cancel the previous task before a repeated setup, or the old observer
/// keeps yielding into its own stream.
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

// MARK: - Observed Values

/// The current value, then each change. Observations on macOS 26; before it, a re-armed
/// withObservationTracking that keeps only the newest value, as Observations does.
@MainActor
func observedValues<Value: Sendable>(
    _ value: @escaping @MainActor () -> Value
) -> AsyncStream<Value> {
    if #available(macOS 26.0, *) {
        let changes = Observations { value() }
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                await forward(changes, to: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    return trackedValues(value)
}

@available(macOS 26.0, *)
@MainActor
private func forward<Value: Sendable>(
    _ changes: Observations<Value, Never>,
    to continuation: AsyncStream<Value>.Continuation
) async {
    for await newValue in changes {
        continuation.yield(newValue)
    }
    continuation.finish()
}

/// The withObservationTracking stream observedValues uses before macOS 26.
@MainActor
func trackedValues<Value: Sendable>(
    _ value: @escaping @MainActor () -> Value
) -> AsyncStream<Value> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let isFinished = OSAllocatedUnfairLock(initialState: false)
        continuation.onTermination = { _ in markFinished(isFinished) }
        trackObservedValue(value, into: continuation, isFinished: isFinished)
    }
}

private nonisolated func markFinished(_ isFinished: OSAllocatedUnfairLock<Bool>) {
    isFinished.withLock { $0 = true }
}

@MainActor
private func trackObservedValue<Value: Sendable>(
    _ value: @escaping @MainActor () -> Value,
    into continuation: AsyncStream<Value>.Continuation,
    isFinished: OSAllocatedUnfairLock<Bool>
) {
    guard !isFinished.withLock({ $0 }) else { return }
    let newValue = withObservationTracking {
        value()
    } onChange: {
        retrackObservedValue(value, into: continuation, isFinished: isFinished)
    }
    continuation.yield(newValue)
}

/// The onChange fires before the change lands, so the value is read again once it has.
private nonisolated func retrackObservedValue<Value: Sendable>(
    _ value: @escaping @MainActor () -> Value,
    into continuation: AsyncStream<Value>.Continuation,
    isFinished: OSAllocatedUnfairLock<Bool>
) {
    Task { @MainActor in
        trackObservedValue(value, into: continuation, isFinished: isFinished)
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
