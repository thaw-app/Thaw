//
//  ThawOnboardingTests.swift
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

    // The onboarding flow is a feature tour only. Permission requests are
    // handled by the standalone permissions window after this tour finishes.
    // Lock the complete sequence so a permission slide cannot be added back
    // accidentally.

    func testWelcomeIsFirst() {
        XCTAssertEqual(ThawTourSlide.allCases.first, .welcome)
    }

    func testFeatureTourSequence() {
        XCTAssertEqual(
            ThawTourSlide.allCases,
            [.welcome, .menuBarManagement, .menuBarAppearance, .hotkeysAutomation, .profiles, .integrations]
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

    // MARK: - Auto-advance

    func testWelcomeDoesNotAutoAdvance() {
        XCTAssertEqual(ThawTourSlide.welcome.autoAdvanceDelay, 0)
    }

    func testEveryLoopingSlideHasAPositiveAutoAdvanceDelay() {
        for slide in ThawTourSlide.allCases where slide != .welcome {
            XCTAssertGreaterThan(slide.autoAdvanceDelay, 0, "\(slide) should auto-advance")
        }
    }
}

// MARK: - ThawManagementMockupModel

@MainActor
final class ThawManagementMockupModelTests: XCTestCase {
    func testRestartResetsToHidden() {
        let model = ThawManagementMockupModel()
        model.itemsHidden = false

        model.restart()

        XCTAssertTrue(model.itemsHidden)
    }

    func testToggleFlipsHiddenState() {
        let model = ThawManagementMockupModel()
        let initial = model.itemsHidden

        model.toggle()
        XCTAssertEqual(model.itemsHidden, !initial)

        model.toggle()
        XCTAssertEqual(model.itemsHidden, initial)
    }
}

// MARK: - ThawAppearanceMockupModel

@MainActor
final class ThawAppearanceMockupModelTests: XCTestCase {
    func testStyleLabelsHasOneEntryPerStyle() {
        XCTAssertEqual(ThawAppearanceMockupModel.styleLabels.count, 3)
        for label in ThawAppearanceMockupModel.styleLabels {
            XCTAssertFalse(label.isEmpty)
        }
    }

    func testRestartResetsStyleIndexToZero() {
        let model = ThawAppearanceMockupModel()
        model.select(2)

        model.restart()

        XCTAssertEqual(model.styleIndex, 0)
    }

    func testSelectUpdatesIndex() {
        let model = ThawAppearanceMockupModel()

        model.select(1)
        XCTAssertEqual(model.styleIndex, 1)

        model.select(2)
        XCTAssertEqual(model.styleIndex, 2)
    }
}

// MARK: - ThawHotkeysMockupModel

@MainActor
final class ThawHotkeysMockupModelTests: XCTestCase {
    func testRestartResetsToNotVisible() {
        let model = ThawHotkeysMockupModel()
        model.itemsVisible = true

        model.restart()

        XCTAssertFalse(model.itemsVisible)
    }

    func testTriggerTogglesVisibility() {
        let model = ThawHotkeysMockupModel()
        let initial = model.itemsVisible

        model.trigger()
        XCTAssertEqual(model.itemsVisible, !initial)

        model.trigger()
        XCTAssertEqual(model.itemsVisible, initial)
    }
}

// MARK: - ThawProfilesMockupModel

@MainActor
final class ThawProfilesMockupModelTests: XCTestCase {
    func testFocusModesHasOneEntryPerProfile() {
        XCTAssertEqual(ThawProfilesMockupModel.focusModes.count, 3)
        for mode in ThawProfilesMockupModel.focusModes {
            XCTAssertFalse(mode.name.isEmpty)
            XCTAssertFalse(mode.symbol.isEmpty)
            XCTAssertFalse(mode.items.isEmpty)
        }
    }

    func testActiveReflectsFocusIndex() {
        let model = ThawProfilesMockupModel()
        XCTAssertEqual(model.active.symbol, ThawProfilesMockupModel.focusModes[0].symbol)

        model.select(1)
        XCTAssertEqual(model.active.symbol, ThawProfilesMockupModel.focusModes[1].symbol)
    }

    func testSelectUpdatesFocusIndex() {
        let model = ThawProfilesMockupModel()

        model.select(2)
        XCTAssertEqual(model.focusIndex, 2)
    }

    func testSelectToCurrentIndexIsNoOp() {
        let model = ThawProfilesMockupModel()
        model.select(1)
        XCTAssertEqual(model.focusIndex, 1)

        model.select(1)
        XCTAssertEqual(model.focusIndex, 1)
    }

    func testRestartResetsFocusIndexToZero() {
        let model = ThawProfilesMockupModel()
        model.select(2)

        model.restart()

        XCTAssertEqual(model.focusIndex, 0)
    }
}
