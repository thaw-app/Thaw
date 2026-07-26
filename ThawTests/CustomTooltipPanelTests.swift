//
//  CustomTooltipPanelTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

@MainActor
final class CustomTooltipPanelTests: XCTestCase {
    func testTooltipAppearsAboveIceBar() {
        let iceBar = IceBarPanel()
        let tooltip = CustomTooltipPanel.shared

        XCTAssertGreaterThan(
            tooltip.level.rawValue,
            iceBar.level.rawValue,
            "Tooltips must be above the Thaw Bar so grid items cannot obscure them"
        )
    }

    // MARK: - placementOrigin

    private let panelSize = NSSize(width: 60, height: 20)

    func testPlacementOriginInsideScreenIsBelowPointAndWithinVisibleFrame() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let point = NSPoint(x: 700, y: 500)

        let origin = CustomTooltipPanel.placementOrigin(
            for: panelSize,
            near: point,
            screens: [(frame: screenFrame, visibleFrame: visibleFrame)],
            preferred: nil
        )

        let unwrapped = try! XCTUnwrap(origin)
        XCTAssertTrue(visibleFrame.contains(NSRect(origin: unwrapped, size: panelSize)))
        XCTAssertLessThan(unwrapped.y, point.y, "Tooltip should be placed below the point")
    }

    func testPlacementOriginOutsideAllScreensReturnsNil() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let point = NSPoint(x: 5000, y: 5000)

        let origin = CustomTooltipPanel.placementOrigin(
            for: panelSize,
            near: point,
            screens: [(frame: screenFrame, visibleFrame: visibleFrame)],
            preferred: nil
        )

        XCTAssertNil(origin, "A point outside every screen must not produce a placement")
    }

    func testPlacementOriginNearBottomEdgeIsClampedInsideVisibleFrame() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let point = NSPoint(x: 700, y: 30)

        let origin = CustomTooltipPanel.placementOrigin(
            for: panelSize,
            near: point,
            screens: [(frame: screenFrame, visibleFrame: visibleFrame)],
            preferred: nil
        )

        let unwrapped = try! XCTUnwrap(origin)
        XCTAssertTrue(visibleFrame.contains(NSRect(origin: unwrapped, size: panelSize)))
    }

    func testPlacementOriginOnSecondScreenClampsToSecondScreenVisibleFrame() {
        let firstFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let firstVisible = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let secondFrame = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let secondVisible = NSRect(x: 1440, y: 25, width: 1920, height: 1055)
        let point = NSPoint(x: 2000, y: 500)

        let origin = CustomTooltipPanel.placementOrigin(
            for: panelSize,
            near: point,
            screens: [
                (frame: firstFrame, visibleFrame: firstVisible),
                (frame: secondFrame, visibleFrame: secondVisible),
            ],
            preferred: nil
        )

        let unwrapped = try! XCTUnwrap(origin)
        XCTAssertTrue(secondVisible.contains(NSRect(origin: unwrapped, size: panelSize)))
        XCTAssertFalse(firstVisible.intersects(NSRect(origin: unwrapped, size: panelSize)))
    }
}
