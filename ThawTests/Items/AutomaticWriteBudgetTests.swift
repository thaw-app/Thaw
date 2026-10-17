//
//  AutomaticWriteBudgetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Automatic passes that keep writing with nobody touching the bar pause, so no loop runs unbounded.
@Suite("Automatic write budget")
struct AutomaticWriteBudgetTests {
    private let start = ContinuousClock.now

    private func at(_ seconds: Int) -> ContinuousClock.Instant {
        start + .seconds(seconds)
    }

    @Test("A few writing passes stay within budget")
    func fewPassesAllowed() {
        var budget = AutomaticWriteBudget()
        for second in 0 ..< AutomaticWriteBudget.limit {
            let tripped = budget.noteWritingPass(at: at(second))
            #expect(!tripped)
        }
        #expect(budget.allowsAutomaticWrites(at: at(5)))
    }

    @Test("One pass over the limit inside the window pauses automatic writes")
    func overLimitPauses() {
        var budget = AutomaticWriteBudget()
        for second in 0 ..< AutomaticWriteBudget.limit {
            budget.noteWritingPass(at: at(second))
        }
        let tripped = budget.noteWritingPass(at: at(10))
        #expect(tripped)
        #expect(!budget.allowsAutomaticWrites(at: at(11)))
    }

    @Test("The pause ends after its length")
    func pauseEnds() {
        var budget = AutomaticWriteBudget()
        for second in 0 ... AutomaticWriteBudget.limit {
            budget.noteWritingPass(at: at(second))
        }
        #expect(!budget.allowsAutomaticWrites(at: at(30)))
        #expect(budget.allowsAutomaticWrites(at: at(70)))
    }

    @Test("Passes spread wider than the window never trip it")
    func spreadPassesAllowed() {
        var budget = AutomaticWriteBudget()
        for pass in 0 ..< 10 {
            let tripped = budget.noteWritingPass(at: at(pass * 20))
            #expect(!tripped)
        }
    }

    @Test("A user action resets the count and lifts a pause")
    func userActionResets() {
        var budget = AutomaticWriteBudget()
        for second in 0 ... AutomaticWriteBudget.limit {
            budget.noteWritingPass(at: at(second))
        }
        budget.noteUserAction()
        #expect(budget.allowsAutomaticWrites(at: at(6)))
        let tripped = budget.noteWritingPass(at: at(7))
        #expect(!tripped)
    }
}
