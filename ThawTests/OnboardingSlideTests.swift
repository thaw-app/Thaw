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

    // The onboarding flow relies on a fixed slide order: `welcome` must be
    // first, and `permissions` must be last. The "Skip" button jumps to
    // `slides.count - 1`, `OnboardingSheet/isLast` gates the first-launch
    // permissions handoff, and the zoom reset keys off the welcome slide.
    // Reordering the enum would silently break those flows, so lock the
    // endpoints here.

    func testWelcomeIsFirst() {
        XCTAssertEqual(OnboardingSlide.allCases.first, .welcome)
    }

    func testPermissionsIsLast() {
        XCTAssertEqual(OnboardingSlide.allCases.last, .permissions)
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
