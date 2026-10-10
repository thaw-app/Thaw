//
//  ConcurrencyHelpers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawCapture

/// The timeout type is shared with the capture package through
/// ThawConcurrency. The alias keeps the name resolvable for the rest of the
/// app, which does not import ThawCapture directly.
typealias TaskTimeoutError = ThawConcurrency.TaskTimeoutError

nonisolated extension Task where Failure == any Error {
    /// Runs the given throwing operation asynchronously as part of a
    /// new unstructured top-level task.
    ///
    /// If the operation does not complete within the provided duration,
    /// the task is cancelled and a TaskTimeoutError is thrown.
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
    /// new unstructured, detached top-level task.
    ///
    /// If the operation does not complete within the provided duration,
    /// the task is cancelled and a TaskTimeoutError is thrown.
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
