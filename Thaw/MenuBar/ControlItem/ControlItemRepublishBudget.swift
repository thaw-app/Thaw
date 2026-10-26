//
//  ControlItemRepublishBudget.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Re-publishes spent per control item this session, and when each item last
/// re-published. ControlItem.republishDecision decides; this only keeps count.
@MainActor
enum ControlItemRepublishBudget {
    private static var spent: [ControlItem.Identifier: Int] = [:]
    private static var lastAttempt: [ControlItem.Identifier: ContinuousClock.Instant] = [:]

    static func attempts(by identifier: ControlItem.Identifier) -> Int {
        spent[identifier, default: 0]
    }

    static func elapsedSinceLastAttempt(by identifier: ControlItem.Identifier, now: ContinuousClock.Instant) -> Duration? {
        lastAttempt[identifier].map { now - $0 }
    }

    static func record(attempt: Int, by identifier: ControlItem.Identifier, at now: ContinuousClock.Instant) {
        spent[identifier] = attempt
        lastAttempt[identifier] = now
    }

    /// Spends the whole budget without re-registering anything.
    static func spendAll(by identifier: ControlItem.Identifier) {
        spent[identifier] = ControlItem.maximumRepublishes
    }

    /// Returns whether any of the budget had been spent.
    @discardableResult
    static func restore(for identifier: ControlItem.Identifier) -> Bool {
        lastAttempt[identifier] = nil
        return spent.removeValue(forKey: identifier) != nil
    }
}
