//
//  MoveEventCoordinatesTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Regression tests for the synthetic event coordinates used to move menu bar items.
final class MoveEventCoordinatesTests: XCTestCase {
    /// Off-screen destinations preserve their horizontal edge while keeping the
    /// event away from the top-left Hot Corner.
    func testOffscreenTargetPointsUseBoundsMidpoint() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let bounds = CGRect(x: -4193, y: 0, width: 22, height: 33)
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 100,
            bounds: bounds,
            isOnScreen: false
        )

        XCTAssertEqual(
            MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ),
            CGPoint(x: bounds.minX, y: bounds.midY)
        )
        XCTAssertEqual(
            MenuBarItemManager.MoveDestination.rightOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ),
            CGPoint(x: bounds.maxX, y: bounds.midY)
        )
    }

    /// The safe vertical coordinate is derived from the target rather than a
    /// hard-coded primary-display inset.
    func testTargetPointUsesMidpointOnVerticallyOffsetDisplay() {
        let displayBounds = CGRect(x: 1200, y: -900, width: 1920, height: 1080)
        let bounds = CGRect(x: -4193, y: -900, width: 24, height: 24)
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 101,
            bounds: bounds
        )

        let point = MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
            in: bounds,
            on: displayBounds
        )

        XCTAssertEqual(point, CGPoint(x: bounds.minX, y: bounds.midY))
        XCTAssertNotEqual(point.y, bounds.minY)
    }

    /// On-screen moves retain their existing top-edge coordinate because those
    /// moves still physically warp the cursor before posting events.
    func testOnscreenTargetPointPreservesExistingYCoordinate() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let bounds = CGRect(x: 1100, y: 0, width: 24, height: 33)
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 102,
            bounds: bounds
        )

        let point = MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
            in: bounds,
            on: displayBounds
        )

        XCTAssertEqual(point, CGPoint(x: bounds.minX, y: bounds.minY))
    }

    /// The notch frame comes from AppKit, so only its horizontal position is
    /// safe to reuse in a Core Graphics event.
    func testNotchMouseDownKeepsCoreGraphicsMenuBarYCoordinate() {
        let notchFrameAppKit = CGRect(x: 646, y: 924, width: 179, height: 32)
        let targetPointCoreGraphics = CGPoint(x: -4193, y: 16.5)

        let point = MenuBarItemManager.notchMouseDownPoint(
            notchFrameAppKit: notchFrameAppKit,
            targetPointCoreGraphics: targetPointCoreGraphics
        )

        XCTAssertEqual(point, CGPoint(x: notchFrameAppKit.midX, y: targetPointCoreGraphics.y))
        XCTAssertNotEqual(point.y, notchFrameAppKit.midY)
    }
}
