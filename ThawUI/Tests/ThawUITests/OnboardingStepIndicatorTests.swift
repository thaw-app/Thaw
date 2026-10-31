//
//  OnboardingStepIndicatorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Suite("Onboarding step indicator")
struct OnboardingStepIndicatorTests {
    private func width(step: Int, total: Int) -> CGFloat {
        let view = OnboardingStepIndicator(step: step, total: total, label: "Spoken")
        return NSHostingView(rootView: view).fittingSize.width
    }

    @Test("The step indicator grows with the number of steps")
    func growsWithSteps() {
        #expect(width(step: 2, total: 3) > width(step: 1, total: 1))
    }

    @Test("No steps still draws one dot instead of an empty range")
    func noSteps() {
        #expect(width(step: 0, total: 0) == width(step: 1, total: 1))
    }

    @Test("VoiceOver reads the label the app gives")
    func spokenLabel() {
        let view = OnboardingStepIndicator(step: 2, total: 3, label: "Second of three")
        #expect(view.label == "Second of three")
    }
}
