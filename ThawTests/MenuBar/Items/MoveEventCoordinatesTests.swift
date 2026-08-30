//
//  MoveEventCoordinatesTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Regression tests for the synthetic event coordinates used to move menu bar items.
@Suite("Move event coordinates")
struct MoveEventCoordinatesTests {
    /// The target point is used unchanged for both halves of a teleport. In
    /// particular, an off-screen press must stay off-screen rather than being
    /// rewritten to a visible notch midpoint, which would flash the real item
    /// in the center of the display before the release.
    @Test("An off-screen teleport keeps its parked destination coordinate")
    func offscreenTeleportKeepsParkedCoordinate() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let bounds = CGRect(x: -4193, y: 0, width: 22, height: 33)
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 100,
            bounds: bounds,
            isOnScreen: false
        )

        #expect(
            MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.minX, y: bounds.midY)
        )
        #expect(
            MenuBarItemManager.MoveDestination.rightOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.maxX, y: bounds.midY)
        )

        let parkedPoint = CGPoint(x: bounds.minX, y: bounds.midY)
        let eventLocations = MenuBarItemManager.moveEventLocations(
            targetPoints: (start: parkedPoint, end: parkedPoint),
            faithfulDragStart: nil
        )
        #expect(eventLocations.press == parkedPoint)
        #expect(eventLocations.release == parkedPoint)
    }

    /// #923: dropping onto the exact coordinate of a section divider leaves
    /// AppKit free to choose either side. The field log showed
    /// `.leftOfItem(AH_ctrl)` repeatedly landing one point to its right.
    @Test("A control-item destination biases the drop into the requested section")
    func controlItemTargetPointUsesRequestedSide() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let bounds = CGRect(x: -9465, y: 0, width: 0, height: 33)
        let target = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 32278,
            bounds: bounds,
            isOnScreen: false
        )

        #expect(
            MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.minX - 1, y: bounds.midY)
        )
        #expect(
            MenuBarItemManager.MoveDestination.rightOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.maxX + 1, y: bounds.midY)
        )
    }

    /// A divider that is thousands of points wide needs the bias just as much
    /// as a zero-width one. The width is how the section conceals the items
    /// behind it, not hit-test slack the drop can lean on: in the reporter's
    /// 21 August log AH_ctrl was parked with `maxX <= 0` and expanded, and
    /// `.leftOfItem` still landed the item at `minX + 1` on attempts 1 and 5.
    @Test("An expanded control-item destination is biased too")
    func expandedControlItemTargetPointIsBiased() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        // The geometry the log implies: minX -9189, maxX at or left of the
        // display origin, which is why targetPoint reaches for midY.
        let bounds = CGRect(x: -9189, y: 0, width: 9189, height: 33)
        let target = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 43471,
            bounds: bounds,
            isOnScreen: false
        )

        #expect(
            MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.minX - 1, y: bounds.midY)
        )
        #expect(
            MenuBarItemManager.MoveDestination.rightOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.maxX + 1, y: bounds.midY)
        )
    }

    /// #1035: the chevron is the anchor TemporaryShow reveals against, and
    /// it was left unbiased because it divides no sections. The reporter's
    /// log shows what that costs — attempt 2 planned `targetMinX=837.0` and
    /// then measured `itemMinX=863.0`, i.e. the item landed to the right of
    /// a 26pt chevron it was supposed to land left of.
    @Test("A chevron destination is biased into the requested side")
    func chevronTargetPointIsBiased() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        // The geometry from the reporter's attempt 2.
        let bounds = CGRect(x: 837, y: 0, width: 26, height: 33)
        let target = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 104,
            bounds: bounds
        )

        let left = MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
            in: bounds,
            on: displayBounds
        )

        #expect(left == CGPoint(x: bounds.minX - 1, y: bounds.minY))
        // The unbiased point was the chevron's own edge, which is the side
        // AppKit got to choose from.
        #expect(left.x != bounds.minX)
        #expect(
            MenuBarItemManager.MoveDestination.rightOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.maxX + 1, y: bounds.minY)
        )
    }

    /// A parked chevron gets the same treatment as a parked section divider.
    @Test("An off-screen chevron destination is biased too")
    func offscreenChevronTargetPointIsBiased() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let bounds = CGRect(x: -4193, y: 0, width: 26, height: 33)
        let target = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 105,
            bounds: bounds,
            isOnScreen: false
        )

        #expect(
            MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.minX - 1, y: bounds.midY)
        )
    }

    /// An ordinary item is not a section boundary, so its edge is a real drop
    /// coordinate and must be left alone.
    @Test("A regular item destination gets no section bias")
    func regularItemTargetPointGetsNoBias() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let bounds = CGRect(x: -4193, y: 0, width: 22, height: 33)
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 103,
            bounds: bounds,
            isOnScreen: false
        )

        #expect(
            MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.minX, y: bounds.midY)
        )
    }

    /// hard-coded primary-display inset.
    @Test("The safe vertical coordinate comes from the target on a vertically offset display")
    func targetPointUsesMidpointOnVerticallyOffsetDisplay() {
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

        #expect(point == CGPoint(x: bounds.minX, y: bounds.midY))
        #expect(point.y != bounds.minY)
    }

    /// On-screen moves retain their existing top-edge coordinate because those
    /// moves still physically warp the cursor before posting events.
    @Test("An on-screen destination keeps its existing top-edge coordinate")
    func onscreenTargetPointPreservesExistingYCoordinate() {
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

        #expect(point == CGPoint(x: bounds.minX, y: bounds.minY))
    }
}
