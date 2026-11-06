//
//  OnboardingOutcomeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The flow returns both choices by value, preserving its defaults.
@Suite("Onboarding outcome")
struct OnboardingOutcomeTests {
    @Test("the flow's defaults round-trip")
    func defaultsRoundTrip() {
        let outcome = OnboardingOutcome(simpleMode: true, automaticUpdates: true)
        #expect(outcome.simpleMode)
        #expect(outcome.automaticUpdates)
        #expect(outcome == OnboardingOutcome(simpleMode: true, automaticUpdates: true))
    }

    @Test("outcomes compare by value")
    func equatableByValue() {
        let full = OnboardingOutcome(simpleMode: false, automaticUpdates: true)
        #expect(full != OnboardingOutcome(simpleMode: true, automaticUpdates: true))
        #expect(full != OnboardingOutcome(simpleMode: false, automaticUpdates: false))

        var copy = full
        copy.simpleMode = true
        copy.automaticUpdates = false
        #expect(copy == OnboardingOutcome(simpleMode: true, automaticUpdates: false))
        #expect(copy != OnboardingOutcome(simpleMode: true, automaticUpdates: true))
    }

    /// The bento alone collects both choices; keep their answers independent when passing them to the host.
    @Test("each field is carried separately", arguments: [false, true], [false, true])
    func fieldsAreIndependent(simpleMode: Bool, automaticUpdates: Bool) {
        let outcome = OnboardingOutcome(simpleMode: simpleMode, automaticUpdates: automaticUpdates)
        #expect(outcome.simpleMode == simpleMode)
        #expect(outcome.automaticUpdates == automaticUpdates)
    }
}
