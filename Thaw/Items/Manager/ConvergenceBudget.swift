//
//  ConvergenceBudget.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// How long automatic ordering passes may keep dragging for one authored edit.
/// When the budget runs out they pause, since they would re-plan the move it gave up on, and resume when the pause ends.
struct ConvergenceBudget {
    /// How long one authored edit may keep spending automatic passes.
    static let budget: Duration = .seconds(90)

    /// How long automatic passes pause once the budget has run out.
    static let pause: Duration = .seconds(600)

    /// What a pass is told when it asks whether it may run.
    enum Verdict: Equatable {
        /// No edit is being converged on, the budget still has time, or the
        /// pause that followed it has ended.
        case open
        /// The budget ran out on this very call; the pause starts now.
        case pauseBegan
        /// Inside the pause.
        case paused
    }

    private var deadline: ContinuousClock.Instant?
    private var pausedUntil: ContinuousClock.Instant?

    /// An authored edit committed: a fresh budget, and no pause left over.
    mutating func open(at now: ContinuousClock.Instant = .now) {
        deadline = now + Self.budget
        pausedUntil = nil
    }

    mutating func verdict(at now: ContinuousClock.Instant = .now) -> Verdict {
        guard let deadline, now >= deadline else { return .open }
        guard let pausedUntil else {
            self.pausedUntil = now + Self.pause
            return .pauseBegan
        }
        guard now >= pausedUntil else { return .paused }
        // The pause has run its course. Passes resume until the next edit.
        self.deadline = nil
        self.pausedUntil = nil
        return .open
    }
}
