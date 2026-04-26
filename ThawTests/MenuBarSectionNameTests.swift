//
//  MenuBarSectionNameTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

// MARK: - MenuBarSection.Name Tests

final class MenuBarSectionNameTests: XCTestCase {
    // MARK: - CaseIterable

    func testAllCasesCount() {
        XCTAssertEqual(MenuBarSection.Name.allCases.count, 3)
    }

    func testAllCasesContainsVisible() {
        XCTAssertTrue(MenuBarSection.Name.allCases.contains(.visible))
    }

    func testAllCasesContainsHidden() {
        XCTAssertTrue(MenuBarSection.Name.allCases.contains(.hidden))
    }

    func testAllCasesContainsAlwaysHidden() {
        XCTAssertTrue(MenuBarSection.Name.allCases.contains(.alwaysHidden))
    }

    // MARK: - displayString

    func testDisplayStringVisible() {
        XCTAssertEqual(MenuBarSection.Name.visible.displayString, "Visible")
    }

    func testDisplayStringHidden() {
        XCTAssertEqual(MenuBarSection.Name.hidden.displayString, "Hidden")
    }

    func testDisplayStringAlwaysHidden() {
        XCTAssertEqual(MenuBarSection.Name.alwaysHidden.displayString, "Always-Hidden")
    }

    func testAllDisplayStringsNonEmpty() {
        for name in MenuBarSection.Name.allCases {
            XCTAssertFalse(name.displayString.isEmpty, "\(name) should have non-empty displayString")
        }
    }

    // MARK: - logString

    func testLogStringVisible() {
        XCTAssertEqual(MenuBarSection.Name.visible.logString, "visible section")
    }

    func testLogStringHidden() {
        XCTAssertEqual(MenuBarSection.Name.hidden.logString, "hidden section")
    }

    func testLogStringAlwaysHidden() {
        XCTAssertEqual(MenuBarSection.Name.alwaysHidden.logString, "always-hidden section")
    }

    func testAllLogStringsContainSection() {
        for name in MenuBarSection.Name.allCases {
            XCTAssertTrue(name.logString.contains("section"), "\(name).logString should contain 'section'")
        }
    }

    // MARK: - localized

    func testLocalizedVisible() {
        // LocalizedStringKey doesn't expose its value directly, but we can verify it exists
        let localized = MenuBarSection.Name.visible.localized
        XCTAssertNotNil(localized)
    }

    func testLocalizedHidden() {
        let localized = MenuBarSection.Name.hidden.localized
        XCTAssertNotNil(localized)
    }

    func testLocalizedAlwaysHidden() {
        let localized = MenuBarSection.Name.alwaysHidden.localized
        XCTAssertNotNil(localized)
    }

    // MARK: - notchGap Static Constant

    func testNotchGapValue() {
        XCTAssertEqual(MenuBarSection.notchGap, 24)
    }

    func testNotchGapIsPositive() {
        XCTAssertGreaterThan(MenuBarSection.notchGap, 0)
    }

    // MARK: - Presentation Mode

    func testPresentationModeUsesInlineWhenItemsAlreadyFit() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 300,
            appMenuRightEdge: 250,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1200,
            notchFrame: nil,
            allowHidingApplicationMenus: false
        )

        XCTAssertEqual(mode, .inline)
    }

    func testPresentationModeFallsBackToIceBarWhenItemsDoNotFitAndHidingMenusIsDisabled() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 1000,
            appMenuRightEdge: 350,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1200,
            notchFrame: nil,
            allowHidingApplicationMenus: false
        )

        XCTAssertEqual(mode, .iceBar)
    }

    func testPresentationModeHidesApplicationMenusBeforeUsingIceBar() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 1000,
            appMenuRightEdge: 350,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1200,
            notchFrame: nil,
            allowHidingApplicationMenus: true
        )

        XCTAssertEqual(mode, .inlineHidingApplicationMenus)
    }

    func testPresentationModeStillUsesIceBarWhenItemsCannotFitEvenAfterHidingMenus() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 1400,
            appMenuRightEdge: 350,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1200,
            notchFrame: nil,
            allowHidingApplicationMenus: true
        )

        XCTAssertEqual(mode, .iceBar)
    }

    func testUsableInlineWidthAccountsForNotchGapOnBothSides() {
        let width = MenuBarSection.usableInlineWidth(
            from: 200,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1600,
            notchFrame: CGRect(x: 700, y: 0, width: 200, height: 30)
        )

        XCTAssertEqual(width, 1152)
    }

    // MARK: - usableInlineWidth

    func testUsableInlineWidthFallsBackToScreenFrameMinXWhenAppMenuRightEdgeIsNil() {
        let width = MenuBarSection.usableInlineWidth(
            from: nil,
            screenFrameMinX: 100,
            screenVisibleMaxX: 1600,
            notchFrame: nil
        )

        XCTAssertEqual(width, 1500)
    }

    func testUsableInlineWidthClampsAppMenuRightEdgeBelowScreenFrameMinX() {
        // appMenuRightEdge(50) < screenFrameMinX(100) → clamped to 100
        let width = MenuBarSection.usableInlineWidth(
            from: 50,
            screenFrameMinX: 100,
            screenVisibleMaxX: 1600,
            notchFrame: nil
        )

        XCTAssertEqual(width, 1500)
    }

    func testUsableInlineWidthReturnsZeroWhenScreenVisibleMaxXEqualsAppMenuRightEdgeNoNotch() {
        let width = MenuBarSection.usableInlineWidth(
            from: 1600,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1600,
            notchFrame: nil
        )

        XCTAssertEqual(width, 0)
    }

    func testUsableInlineWidthReturnsZeroWhenScreenVisibleMaxXIsLessThanAppMenuRightEdgeNoNotch() {
        let width = MenuBarSection.usableInlineWidth(
            from: 1700,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1600,
            notchFrame: nil
        )

        XCTAssertEqual(width, 0)
    }

    func testUsableInlineWidthClampsLeftRegionToZeroWhenNotchOverlapsAppMenu() {
        // notchFrame.minX(300) - notchGap(24) = 276 < appMenuRightEdge(400) → leftWidth = 0
        // rightWidth = max(0, 1600 - (500 + 24)) = 1076
        let width = MenuBarSection.usableInlineWidth(
            from: 400,
            screenFrameMinX: 0,
            screenVisibleMaxX: 1600,
            notchFrame: CGRect(x: 300, y: 0, width: 200, height: 30)
        )

        XCTAssertEqual(width, 1076)
    }

    func testUsableInlineWidthClampsRightRegionToZeroWhenScreenEndsBeforeNotchEnds() {
        // screenVisibleMaxX(920) < notchFrame.maxX(900) + notchGap(24) = 924 → rightWidth = 0
        // leftWidth = max(0, 700 - 24 - 200) = 476
        let width = MenuBarSection.usableInlineWidth(
            from: 200,
            screenFrameMinX: 0,
            screenVisibleMaxX: 920,
            notchFrame: CGRect(x: 700, y: 0, width: 200, height: 30)
        )

        XCTAssertEqual(width, 476)
    }

    func testUsableInlineWidthReturnsZeroWhenBothNotchRegionsCollapse() {
        // appMenuRightEdge(750) > notchFrame.minX(700) - notchGap(24) → leftWidth = 0
        // screenVisibleMaxX(910) < notchFrame.maxX(900) + notchGap(24) = 924 → rightWidth = 0
        let width = MenuBarSection.usableInlineWidth(
            from: 750,
            screenFrameMinX: 0,
            screenVisibleMaxX: 910,
            notchFrame: CGRect(x: 700, y: 0, width: 200, height: 30)
        )

        XCTAssertEqual(width, 0)
    }
}
