//
//  MenuBarSectionCapacityTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class MenuBarSectionCapacityTests: XCTestCase {
    func testNotchGapValue() {
        XCTAssertEqual(MenuBarSection.notchGap, 24)
    }

    func testNotchGapIsPositive() {
        XCTAssertGreaterThan(MenuBarSection.notchGap, 0)
    }

    private func capacity(
        width: CGFloat = 1200,
        appMenuRightEdge: CGFloat? = 250,
        notchFrame: CGRect? = nil
    ) -> MenuBarCapacitySnapshot {
        MenuBarCapacitySnapshot(
            displayID: 1,
            displayBounds: CGRect(x: 0, y: 0, width: width, height: 800),
            notchFrame: notchFrame,
            applicationMenuFrame: appMenuRightEdge.map {
                CGRect(x: 0, y: 0, width: $0, height: 30)
            },
            trailingBoundary: width,
            overflowControlBounds: []
        )
    }

    func testPresentationModeUsesInlineWhenItemsAlreadyFit() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 300,
            capacity: capacity(),
            allowHidingApplicationMenus: false
        )

        XCTAssertEqual(mode, .inline)
    }

    func testPresentationModeFallsBackToIceBarWhenItemsDoNotFitAndHidingMenusIsDisabled() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 1000,
            capacity: capacity(appMenuRightEdge: 350),
            allowHidingApplicationMenus: false
        )

        XCTAssertEqual(mode, .iceBar)
    }

    func testPresentationModeHidesApplicationMenusBeforeUsingIceBar() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 1000,
            capacity: capacity(appMenuRightEdge: 350),
            allowHidingApplicationMenus: true
        )

        XCTAssertEqual(mode, .inlineHidingApplicationMenus)
    }

    func testPresentationModeStillUsesIceBarWhenItemsCannotFitEvenAfterHidingMenus() {
        let mode = MenuBarSection.presentationMode(
            totalItemsWidth: 1400,
            capacity: capacity(appMenuRightEdge: 350),
            allowHidingApplicationMenus: true
        )

        XCTAssertEqual(mode, .iceBar)
    }

    func testUsableInlineWidthAccountsForNotchGapOnBothSides() {
        let width = capacity(
            width: 1600,
            appMenuRightEdge: 200,
            notchFrame: CGRect(x: 700, y: 0, width: 200, height: 30)
        ).availableWidth(
            in: .inline,
            applicationMenus: .visible
        )

        XCTAssertEqual(width, 1152)
    }
}
