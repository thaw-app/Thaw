//
//  MoveEventCoordinatesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@Suite("Move event coordinates")
struct MoveEventCoordinatesTests {
    /// Both halves of a teleport use the target point unchanged. An off-screen press
    /// must stay off-screen; a visible notch midpoint would flash the real item.
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

    /// Tahoe can reject a parked-item teleport that posts both halves at the
    /// destination; a retry presses on the item and releases at the destination (#1058).
    @Test("A source-anchored retry presses on the item and releases at the destination")
    func sourceAnchoredRetryUsesSeparateCoordinates() {
        let source = CGPoint(x: -4432, y: 15)
        let destination = CGPoint(x: -5202, y: 15)

        let eventLocations = MenuBarItemManager.moveEventLocations(
            targetPoints: (start: destination, end: destination),
            faithfulDragStart: nil,
            sourceAnchoredStart: source
        )

        #expect(eventLocations.press == source)
        #expect(eventLocations.release == destination)
    }

    @Test("Faithful drag takes precedence over a source-anchored retry")
    func faithfulDragStartTakesPrecedence() {
        let faithfulStart = CGPoint(x: 100, y: 15)
        let source = CGPoint(x: -4432, y: 15)
        let destination = CGPoint(x: -5202, y: 15)

        let eventLocations = MenuBarItemManager.moveEventLocations(
            targetPoints: (start: destination, end: destination),
            faithfulDragStart: faithfulStart,
            sourceAnchoredStart: source
        )

        #expect(eventLocations.press == faithfulStart)
        #expect(eventLocations.release == destination)
    }

    /// Dropping on a divider's exact coordinate lets AppKit pick either side;
    /// `.leftOfItem(AH_ctrl)` kept landing one point to its right (#923).
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

    /// A thousands-of-points-wide divider needs the bias too: the width conceals
    /// items, it is not hit-test slack. A parked, expanded AH_ctrl still landed
    /// `.leftOfItem` moves at minX + 1.
    @Test("An expanded control-item destination is biased too")
    func expandedControlItemTargetPointIsBiased() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        // Geometry from the log: maxX at or left of the display origin, hence midY.
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

    /// The chevron is TemporaryShow's reveal anchor and was left unbiased because it
    /// divides no sections; a move planned at minX 837 landed at 863, right of a 26pt chevron (#1035).
    @Test("A chevron destination is biased into the requested side")
    func chevronTargetPointIsBiased() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
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
        // The unbiased point was the chevron's own edge, which AppKit could resolve either way.
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

    /// Uses the target's display, not a hard-coded primary-display inset.
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

    /// On-screen moves keep the top-edge coordinate because they still warp the cursor.
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

    // MARK: - Parked release point

    /// A parked teleport must keep the point planned before the press: a held
    /// item reads at the display origin and its lane reflows by ~1000pt.
    @Test("A parked teleport keeps the release point planned before the press")
    func parkedTeleportKeepsPlannedReleasePoint() {
        #expect(
            MenuBarItemManager.MoveStrategy.parkedTeleport.keepsPlannedReleasePoint(
                targetDisposition: .parked
            )
        )
        #expect(
            MenuBarItemManager.MoveStrategy.parkedTeleport.keepsPlannedReleasePoint(
                targetDisposition: .selectedDisplay
            )
        )
    }

    /// A source-anchored retry keeps the planned point only when its
    /// destination is parked; a visible destination's reflow is real.
    @Test("A source-anchored retry keeps the planned point only for a parked destination")
    func sourceAnchoredRetryKeepsPlannedPointOnlyWhenTargetParked() {
        #expect(
            MenuBarItemManager.MoveStrategy.sourceAnchoredTeleport.keepsPlannedReleasePoint(
                targetDisposition: .parked
            )
        )
        #expect(
            !MenuBarItemManager.MoveStrategy.sourceAnchoredTeleport.keepsPlannedReleasePoint(
                targetDisposition: .selectedDisplay
            )
        )
    }

    @Test("Other transports always re-resolve their release point")
    func otherTransportsReresolveReleasePoint() {
        for strategy in [
            MenuBarItemManager.MoveStrategy.teleport,
            .faithfulDrag,
            .crossNotchTeleport,
        ] {
            #expect(!strategy.keepsPlannedReleasePoint(targetDisposition: .parked))
            #expect(!strategy.keepsPlannedReleasePoint(targetDisposition: .selectedDisplay))
        }
    }
}
