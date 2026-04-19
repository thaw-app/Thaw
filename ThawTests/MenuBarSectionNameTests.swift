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

        XCTAssertEqual(width, 1052)
    }
}
