//
//  SyntheticClickBudget.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A cap on the clicks Thaw posts itself, across every item: a loop of
/// retries or reveals can't flood the event stream while the user works.
nonisolated struct SyntheticClickBudget {
    /// More than a person clicks through the Thaw Bar, far less than a runaway loop.
    static let limit = 12
    static let window: Duration = .seconds(10)

    private var stamps: [ContinuousClock.Instant] = []

    /// Spends one click, or returns false when the window is already full.
    mutating func take(now: ContinuousClock.Instant = .now) -> Bool {
        stamps.removeAll { now - $0 >= Self.window }
        guard stamps.count < Self.limit else { return false }
        stamps.append(now)
        return true
    }
}

/// The one budget the click path spends from.
@MainActor
enum SyntheticClickBudgetStore {
    static var shared = SyntheticClickBudget()
}
