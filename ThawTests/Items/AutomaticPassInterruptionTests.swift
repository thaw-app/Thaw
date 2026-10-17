//
//  AutomaticPassInterruptionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

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
