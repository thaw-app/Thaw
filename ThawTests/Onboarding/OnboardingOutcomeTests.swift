//
//  OnboardingOutcomeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Onboarding outcome")
struct OnboardingOutcomeTests {
    @Test("A first onboarding starts in Simple Mode, whatever the mode was")
    func firstOnboardingStartsSimple() {
        #expect(OnboardingOutcome.simpleMode(current: false, hasSeenOnboarding: false))
        #expect(OnboardingOutcome.simpleMode(current: true, hasSeenOnboarding: false))
    }

    @Test("A replay or an upgrade keeps the mode in use", arguments: [false, true])
    func replayKeepsMode(current: Bool) {
        #expect(OnboardingOutcome.simpleMode(current: current, hasSeenOnboarding: true) == current)
    }
}
