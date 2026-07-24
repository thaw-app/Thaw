//
//  OnboardingSlideTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

// MARK: - ThawTourSlide Tests

final class ThawTourSlideTests: XCTestCase {
    // MARK: - Ordering invariant

    // The tour relies on a fixed slide order: `welcome` must be first, and
    // the remaining slides loop back to `menuBarManagement` once the last
    // one finishes. Reordering the enum would silently break that loop, so
    // lock the endpoints here.

    func testWelcomeIsFirst() {
        XCTAssertEqual(ThawTourSlide.allCases.first, .welcome)
    }

    func testProfilesIsLast() {
        XCTAssertEqual(ThawTourSlide.allCases.last, .profiles)
    }

    // MARK: - id

    func testIdMatchesRawValue() {
        for slide in ThawTourSlide.allCases {
            XCTAssertEqual(slide.id, slide.rawValue)
        }
    }

    // MARK: - Content

    func testEveryCaseHasNonEmptyTitleAndDescription() {
        for slide in ThawTourSlide.allCases {
            XCTAssertFalse(slide.title.isEmpty, "title for \(slide) should not be empty")
            XCTAssertFalse(slide.description.isEmpty, "description for \(slide) should not be empty")
        }
    }

    // MARK: - autoAdvanceDelay

    func testWelcomeHasNoAutoAdvanceDelay() {
        XCTAssertEqual(ThawTourSlide.welcome.autoAdvanceDelay, 0)
    }

    func testLoopingSlidesHavePositiveAutoAdvanceDelay() {
        for slide in ThawTourSlide.allCases where slide != .welcome {
            XCTAssertGreaterThan(slide.autoAdvanceDelay, 0, "\(slide) should auto-advance")
        }
    }
}
