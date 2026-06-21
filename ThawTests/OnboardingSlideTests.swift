//
//  OnboardingSlideTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

// MARK: - OnboardingSlide Tests

final class OnboardingSlideTests: XCTestCase {
    // MARK: - Ordering invariant

    // The onboarding flow is a feature tour only. Permission requests are
    // handled by the standalone permissions window before this tour appears.
    // Lock the complete sequence so a permission slide cannot be added back
    // accidentally.

    func testWelcomeIsFirst() {
        XCTAssertEqual(OnboardingSlide.allCases.first, .welcome)
    }

    func testFeatureTourSequence() {
        XCTAssertEqual(
            OnboardingSlide.allCases,
            [.welcome, .menuBarManagement, .menuBarAppearance, .hotkeysAutomation, .profiles]
        )
    }

    func testFirstLaunchPermissionsFlowStartsWithOnboarding() {
        XCTAssertEqual(
            PermissionsFlowStage(hasSeenOnboarding: false, hasCompletedFirstLaunch: false),
            .onboarding
        )
    }

    func testPermissionsFlowSkipsOnboardingAfterItWasSeen() {
        XCTAssertEqual(
            PermissionsFlowStage(hasSeenOnboarding: true, hasCompletedFirstLaunch: false),
            .permissions
        )
    }

    // MARK: - id

    func testIdMatchesRawValue() {
        for slide in OnboardingSlide.allCases {
            XCTAssertEqual(slide.id, slide.rawValue)
        }
    }

    // MARK: - Content

    func testEveryCaseHasNonEmptyTitleAndDescription() {
        for slide in OnboardingSlide.allCases {
            XCTAssertFalse(String(localized: slide.title).isEmpty, "title for \(slide) should not be empty")
            XCTAssertFalse(String(localized: slide.description).isEmpty, "description for \(slide) should not be empty")
        }
    }
}
