//
//  ReducedModeChoiceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Reduced mode choice", .serialized, .scratchDefaults)
struct ReducedModeChoiceTests {
    @Test("Choosing it from Troubleshooting keeps it with Accessibility granted")
    func troubleshootingChoiceIsKept() {
        ReducedModeController.choose(keepingWithAccessibility: true)
        #expect(ReducedModeController.isChosen)
        #expect(ReducedModeController.isKeptWithAccessibility)
    }

    @Test("Onboarding's choice still gives way to the full app once access is granted")
    func onboardingChoiceGivesWay() {
        ReducedModeController.isChosen = true
        #expect(!ReducedModeController.isKeptWithAccessibility)
    }

    @Test("Switching to the full app clears both, however it was chosen")
    func leavingClearsBoth() {
        ReducedModeController.choose(keepingWithAccessibility: true)
        ReducedModeController.leave()
        #expect(!ReducedModeController.isChosen)
        #expect(!ReducedModeController.isKeptWithAccessibility)
    }
}
