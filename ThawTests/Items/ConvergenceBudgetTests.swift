//
//  ConvergenceBudgetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Automatic ordering passes pause after an edit's budget, then resume")
struct ConvergenceBudgetTests {
    @Test("With no authored edit, passes are never paused")
    func idleIsOpen() {
        var budget = ConvergenceBudget()
        #expect(budget.verdict() == .open)
    }

    @Test("An authored edit leaves passes open for the length of the budget")
    func openWithinTheBudget() {
        var budget = ConvergenceBudget()
        let start = ContinuousClock.now
        budget.open(at: start)

        #expect(budget.verdict(at: start + .seconds(1)) == .open)
        #expect(budget.verdict(at: start + ConvergenceBudget.budget - .seconds(1)) == .open)
    }

    @Test("Running out of budget starts the pause once, and the pause holds")
    func exhaustionPauses() {
        var budget = ConvergenceBudget()
        let start = ContinuousClock.now
        budget.open(at: start)
        let spent = start + ConvergenceBudget.budget

        #expect(budget.verdict(at: spent) == .pauseBegan)
        #expect(budget.verdict(at: spent + .seconds(1)) == .paused)
        #expect(budget.verdict(at: spent + ConvergenceBudget.pause - .seconds(1)) == .paused)
    }

    @Test("When the pause ends, passes resume and stay resumed")
    func pauseEnds() {
        var budget = ConvergenceBudget()
        let start = ContinuousClock.now
        budget.open(at: start)
        let spent = start + ConvergenceBudget.budget
        #expect(budget.verdict(at: spent) == .pauseBegan)
        let over = spent + ConvergenceBudget.pause

        #expect(budget.verdict(at: over) == .open)
        // It used to start another pause here, and another after that.
        #expect(budget.verdict(at: over + .seconds(1)) == .open)
        #expect(budget.verdict(at: over + ConvergenceBudget.pause * 3) == .open)
    }

    @Test("A new authored edit during the pause opens a fresh budget")
    func editReopens() {
        var budget = ConvergenceBudget()
        let start = ContinuousClock.now
        budget.open(at: start)
        let spent = start + ConvergenceBudget.budget
        #expect(budget.verdict(at: spent) == .pauseBegan)

        budget.open(at: spent + .seconds(5))
        #expect(budget.verdict(at: spent + .seconds(6)) == .open)
    }
}
