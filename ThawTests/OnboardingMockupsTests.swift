//
//  OnboardingMockupsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
@testable import Thaw
import XCTest

// MARK: - MenuBarTint

final class MenuBarTintTests: XCTestCase {
    func testDarkColorScheme() {
        let tint = MenuBarTint(colorScheme: .dark)
        XCTAssertEqual(tint.background, Color.black.opacity(0.5))
        XCTAssertEqual(tint.label, .white)
    }

    func testLightColorScheme() {
        let tint = MenuBarTint(colorScheme: .light)
        XCTAssertEqual(tint.background, Color.white.opacity(0.6))
        XCTAssertEqual(tint.label, .black)
    }
}

// MARK: - MenuBarDemoItems

final class MenuBarDemoItemsTests: XCTestCase {
    func testHiddenSymbolsAreStable() {
        XCTAssertEqual(MenuBarDemoItems.hidden, ["wifi", "battery.100", "speaker.wave.2"])
    }
}

// MARK: - OnboardingZoomSpec

final class OnboardingZoomSpecTests: XCTestCase {
    func testNoneDoesNotZoom() {
        XCTAssertEqual(OnboardingZoomSpec.none.scale, 1)
        XCTAssertEqual(OnboardingZoomSpec.none.corner, .center)
    }

    func testFeatureTourZoomsTowardTopTrailing() {
        XCTAssertEqual(OnboardingZoomSpec.featureTour.scale, 2.0)
        XCTAssertEqual(OnboardingZoomSpec.featureTour.corner, UnitPoint(x: 1.1, y: 0.0))
    }
}

// MARK: - MockupTimeline

@MainActor
final class MockupTimelineTests: XCTestCase {
    func testRestartReturnsIncrementingGenerations() {
        let timeline = MockupTimeline()
        XCTAssertEqual(timeline.restart(), 1)
        XCTAssertEqual(timeline.restart(), 2)
        XCTAssertEqual(timeline.restart(), 3)
    }

    func testScheduleRunsActionForCurrentGeneration() {
        let timeline = MockupTimeline()
        let gen = timeline.restart()

        let expectation = expectation(description: "action runs")
        timeline.schedule(after: 0.01, generation: gen) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testScheduleDropsActionFromStaleGeneration() {
        let timeline = MockupTimeline()
        let staleGen = timeline.restart()
        timeline.restart()

        let notCalled = expectation(description: "stale action does not run")
        notCalled.isInverted = true
        timeline.schedule(after: 0.01, generation: staleGen) {
            notCalled.fulfill()
        }
        wait(for: [notCalled], timeout: 0.2)
    }
}

// MARK: - ManagementMockupModel

@MainActor
final class ManagementMockupModelTests: XCTestCase {
    func testRestartResetsToHidden() {
        let model = ManagementMockupModel()
        model.itemsHidden = false

        model.restart()

        XCTAssertTrue(model.itemsHidden)
    }

    func testToggleFlipsHiddenState() {
        let model = ManagementMockupModel()
        let initial = model.itemsHidden

        model.toggle()
        XCTAssertEqual(model.itemsHidden, !initial)

        model.toggle()
        XCTAssertEqual(model.itemsHidden, initial)
    }
}

// MARK: - AppearanceMockupModel

@MainActor
final class AppearanceMockupModelTests: XCTestCase {
    func testStyleLabelsHasOneEntryPerStyle() {
        XCTAssertEqual(AppearanceMockupModel.styleLabels.count, 3)
        for label in AppearanceMockupModel.styleLabels {
            XCTAssertFalse(label.isEmpty)
        }
    }

    func testRestartResetsStyleIndexToZero() {
        let model = AppearanceMockupModel()
        model.selectStyle(2)

        model.restart()

        XCTAssertEqual(model.styleIndex, 0)
    }

    func testSelectStyleUpdatesIndex() {
        let model = AppearanceMockupModel()

        model.selectStyle(1)
        XCTAssertEqual(model.styleIndex, 1)

        model.selectStyle(2)
        XCTAssertEqual(model.styleIndex, 2)
    }

    func testSelectStyleToCurrentIndexIsNoOp() {
        let model = AppearanceMockupModel()
        model.selectStyle(1)
        XCTAssertEqual(model.styleIndex, 1)

        model.selectStyle(1)
        XCTAssertEqual(model.styleIndex, 1)
    }
}

// MARK: - HotkeysMockupModel

@MainActor
final class HotkeysMockupModelTests: XCTestCase {
    func testRestartResetsToNotVisible() {
        let model = HotkeysMockupModel()
        model.itemsVisible = true

        model.restart()

        XCTAssertFalse(model.itemsVisible)
    }

    func testTriggerHotkeyTogglesVisibility() {
        let model = HotkeysMockupModel()
        let initial = model.itemsVisible

        model.triggerHotkey()
        XCTAssertEqual(model.itemsVisible, !initial)

        model.triggerHotkey()
        XCTAssertEqual(model.itemsVisible, initial)
    }
}

// MARK: - ProfilesMockupModel

@MainActor
final class ProfilesMockupModelTests: XCTestCase {
    func testFocusModesHasOneEntryPerProfile() {
        XCTAssertEqual(ProfilesMockupModel.focusModes.count, 3)
        for mode in ProfilesMockupModel.focusModes {
            XCTAssertFalse(mode.name.isEmpty)
            XCTAssertFalse(mode.symbol.isEmpty)
            XCTAssertFalse(mode.items.isEmpty)
        }
    }

    func testActiveReflectsFocusIndex() {
        let model = ProfilesMockupModel()
        XCTAssertEqual(model.active.symbol, ProfilesMockupModel.focusModes[0].symbol)

        model.switchFocus(to: 1)
        XCTAssertEqual(model.active.symbol, ProfilesMockupModel.focusModes[1].symbol)
    }

    func testSwitchFocusUpdatesIndex() {
        let model = ProfilesMockupModel()

        model.switchFocus(to: 2)
        XCTAssertEqual(model.focusIndex, 2)
    }

    func testSwitchFocusToCurrentIndexIsNoOp() {
        let model = ProfilesMockupModel()
        model.switchFocus(to: 1)
        XCTAssertEqual(model.focusIndex, 1)

        model.switchFocus(to: 1)
        XCTAssertEqual(model.focusIndex, 1)
    }

    func testRestartResetsFocusIndexToZero() {
        let model = ProfilesMockupModel()
        model.switchFocus(to: 2)

        model.restart()

        XCTAssertEqual(model.focusIndex, 0)
    }
}
