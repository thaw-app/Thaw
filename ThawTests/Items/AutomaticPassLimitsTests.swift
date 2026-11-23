//
//  AutomaticPassLimitsTests.swift
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

/// User input calls off the automatic passes asked for before it, and keeps the ones the user asked for.
@Suite("Automatic pass interruption")
struct AutomaticPassInterruptionTests {
    @Test("A pass asked for before user input is called off; one asked for after is not")
    func inputCallsOffEarlierRequests() {
        var interruption = AutomaticPassInterruption()
        interruption.noteRequest(.postRestrictionRepair, byUser: false)
        #expect(!interruption.isCalledOff(.postRestrictionRepair))

        #expect(interruption.noteUserInput() == [.postRestrictionRepair])
        #expect(interruption.isCalledOff(.postRestrictionRepair))

        interruption.noteRequest(.postRestrictionRepair, byUser: false)
        #expect(!interruption.isCalledOff(.postRestrictionRepair))
    }

    @Test("Work never asked for is never called off")
    func unrequestedWork() {
        var interruption = AutomaticPassInterruption()
        interruption.noteUserInput()
        #expect(!interruption.isCalledOff(.storeHygiene))
    }

    @Test("A pass the user asked for keeps its turn across later input")
    func userRequestedPassSurvives() {
        var interruption = AutomaticPassInterruption()
        interruption.noteRequest(.structuralNormalization, byUser: true)
        interruption.noteRequest(.structuralNormalization, byUser: false)
        #expect(interruption.noteUserInput().isEmpty)
        #expect(!interruption.isCalledOff(.structuralNormalization))
    }

    @Test("A pass is listed only by the input that called it off")
    func calledOffOnce() {
        var interruption = AutomaticPassInterruption()
        interruption.noteRequest(.overflowRebalance, byUser: false)
        #expect(interruption.noteUserInput() == [.overflowRebalance])
        #expect(interruption.noteUserInput().isEmpty)
        #expect(interruption.isCalledOff(.overflowRebalance))
    }

    @Test("A running automatic pass is interrupted by later input, not by earlier input")
    func runningPassIsInterrupted() {
        var interruption = AutomaticPassInterruption()
        interruption.noteUserInput()
        interruption.noteRequest(.postRestrictionRepair, byUser: false)
        interruption.noteStarted(.postRestrictionRepair)
        #expect(!interruption.isInterrupted(.postRestrictionRepair))

        interruption.noteUserInput()
        #expect(interruption.isInterrupted(.postRestrictionRepair))

        interruption.noteFinished(.postRestrictionRepair)
        #expect(!interruption.isInterrupted(.postRestrictionRepair))
    }

    @Test("A running pass the user asked for is not interrupted")
    func runningUserPassContinues() {
        var interruption = AutomaticPassInterruption()
        interruption.noteRequest(.structuralNormalization, byUser: true)
        interruption.noteStarted(.structuralNormalization)
        interruption.noteUserInput()
        #expect(!interruption.isInterrupted(.structuralNormalization))
    }

    @Test("A withdrawn request can no longer be called off")
    func forgetDropsTheStamp() {
        var interruption = AutomaticPassInterruption()
        interruption.noteRequest(.arrivalOrderRestore, byUser: false)
        interruption.forget(.arrivalOrderRestore)
        #expect(interruption.noteUserInput().isEmpty)
        #expect(!interruption.isCalledOff(.arrivalOrderRestore))
    }

    @Test("A finished pass the user asked for doesn't lend its stamp to a later automatic request")
    func finishedUserPassLeavesNoStamp() {
        var interruption = AutomaticPassInterruption()
        interruption.noteRequest(.structuralNormalization, byUser: true)
        interruption.noteStarted(.structuralNormalization)
        interruption.noteFinished(.structuralNormalization)
        #expect(interruption.noteUserInput().isEmpty)

        interruption.noteRequest(.structuralNormalization, byUser: false)
        #expect(interruption.noteUserInput() == [.structuralNormalization])
        #expect(interruption.isCalledOff(.structuralNormalization))
    }

    @Test("A pass that ran is not called off by input after it, without a new request")
    func startedPassUsesUpItsRequest() {
        var interruption = AutomaticPassInterruption()
        interruption.noteRequest(.postRestrictionRepair, byUser: false)
        interruption.noteStarted(.postRestrictionRepair)
        interruption.noteFinished(.postRestrictionRepair)
        #expect(interruption.noteUserInput().isEmpty)
        #expect(!interruption.isCalledOff(.postRestrictionRepair))
    }
}

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
