//
//  OneShotContinuation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import os.lock

/// Cancellation can settle before registration because withTaskCancellationHandler runs immediately for cancelled tasks.
/// Store that result until registration so cancellation is not lost and callers do not wait out the deadline.
public final class OneShotContinuation<T: Sendable, E: Error>: Sendable {
    private enum State {
        case open
        case awaiting(CheckedContinuation<T, E>)
        case settled(Result<T, E>)
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.open)

    public init() {}

    /// Resume immediately if a result settled before registration.
    public func setContinuation(_ continuation: CheckedContinuation<T, E>) {
        let settled = lock.withLock { state -> Result<T, E>? in
            switch state {
            case .open:
                state = .awaiting(continuation)
                return nil
            case .awaiting:
                // Duplicate registration is a caller bug; retain the first continuation as the sole resume owner.
                return nil
            case let .settled(result):
                return result
            }
        }
        if let settled {
            continuation.resume(with: settled)
        }
    }

    /// Store results until registration; only the first settle takes effect, preventing double resume.
    public func settle(_ result: Result<T, E>) {
        let continuation = lock.withLock { state -> CheckedContinuation<T, E>? in
            switch state {
            case .open:
                state = .settled(result)
                return nil
            case let .awaiting(continuation):
                state = .settled(result)
                return continuation
            case .settled:
                return nil
            }
        }
        continuation?.resume(with: result)
    }
}
