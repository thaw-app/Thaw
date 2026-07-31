//
//  OnboardingSlideTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

// MARK: - ThawTourSlide Tests

@Suite("Thaw tour slides")
struct ThawTourSlideTests {
    // MARK: - Ordering invariant

    // The tour relies on a fixed slide order: `welcome` must be first, and
    // the remaining slides loop back to `menuBarManagement` once the last
    // one finishes. Reordering the enum would silently break that loop, so
    // lock the endpoints here.

    @Test("Welcome is the first slide")
    func welcomeIsFirst() {
        #expect(ThawTourSlide.allCases.first == .welcome)
    }

    @Test("Profiles is the last slide")
    func profilesIsLast() {
        #expect(ThawTourSlide.allCases.last == .profiles)
    }

    // MARK: - id

    @Test("Each slide's identifier matches its raw value")
    func idMatchesRawValue() {
        for slide in ThawTourSlide.allCases {
            #expect(slide.id == slide.rawValue)
        }
    }

    // MARK: - Content

    @Test("Every case has a non-empty title and description")
    func everyCaseHasNonEmptyTitleAndDescription() {
        for slide in ThawTourSlide.allCases {
            #expect(!slide.title.isEmpty, "title for \(slide) should not be empty")
            #expect(!slide.description.isEmpty, "description for \(slide) should not be empty")
        }
    }

    // MARK: - autoAdvanceDelay

    @Test("Welcome has no auto-advance delay")
    func welcomeHasNoAutoAdvanceDelay() {
        #expect(ThawTourSlide.welcome.autoAdvanceDelay == 0)
    }

    @Test("Looping slides have a positive auto-advance delay")
    func loopingSlidesHavePositiveAutoAdvanceDelay() {
        for slide in ThawTourSlide.allCases where slide != .welcome {
            #expect(slide.autoAdvanceDelay > 0, "\(slide) should auto-advance")
        }
    }
}
