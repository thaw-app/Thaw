//
//  SyntheticMoveVerification.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

@MainActor
enum SyntheticMoveVerification {
    /// Observes immediately, then at most twice within the settle budget; slow AX calls must not trigger bursts of full-bar walks.
    /// The pointer must already be restored.
    static func observe<Value>(
        budget: Duration,
        now: () -> Duration,
        sleep: (Duration) async throws -> Void,
        snapshot: () async -> Value,
        isSatisfied: (Value) -> Bool
    ) async throws -> (value: Value, satisfied: Bool) {
        let deadline = now() + budget
        for observation in 0 ..< 3 {
            try Task.checkCancellation()
            let value = await snapshot()
            try Task.checkCancellation()
            if isSatisfied(value) {
                return (value, true)
            }
            if observation == 2 || now() >= deadline {
                return (value, false)
            }
            try await sleep(min(budget / 2, deadline - now()))
        }
        preconditionFailure("Every final observation returns")
    }
}
