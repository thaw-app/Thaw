//
//  MoveGestureTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Tests for the pure faithful-drag gesture builder used by the on-item drop
/// strategy. The geometry is exercised without a live menu bar.
@Suite("Move gesture")
struct MoveGestureTests {
    private typealias Gesture = MenuBarItemManager.MoveGesture
    private typealias Path = MenuBarItemManager.HorizontalPathDisposition
    private typealias Transport = MenuBarItemManager.MoveTransportDecision

    /// A gesture is a well-formed drag: it opens with a mouse-down on the
    /// press point and closes with a mouse-up on the destination, with a
    /// settling drag onto the destination just before the release.
    @Test("A faithful drag opens with a down on the item and closes with an up on the destination")
    func gestureIsWellFormed() {
        let start = CGPoint(x: 1452, y: 16.5)
        let end = CGPoint(x: -3725, y: 16.5)

        let steps = Gesture.faithfulDrag(start: start, end: end, intermediateSteps: 3)

        #expect(steps.first == Gesture.Step(subtype: .mouseDown, point: start))
        #expect(steps.last == Gesture.Step(subtype: .mouseUp, point: end))
        #expect(steps.dropLast().last == Gesture.Step(subtype: .mouseDragged, point: end))
        // down + 3 interpolated drags + settle drag + up.
        #expect(steps.count == 6)
        // Exactly one down and one up; everything else is a drag.
        #expect(steps.count(where: { $0.subtype == .mouseDown }) == 1)
        #expect(steps.count(where: { $0.subtype == .mouseUp }) == 1)
        #expect(steps.count(where: { $0.subtype == .mouseDragged }) == 4)
    }

    /// The gesture always contains at least one interpolated drag, even when
    /// the caller asks for none, so the item is never teleported by a bare
    /// down/up pair on this path.
    @Test("The intermediate step count is clamped to at least one")
    func intermediateStepsAreClamped() {
        let start = CGPoint(x: 1000, y: 16.5)
        let end = CGPoint(x: 200, y: 16.5)

        let zero = Gesture.faithfulDrag(start: start, end: end, intermediateSteps: 0)
        let negative = Gesture.faithfulDrag(start: start, end: end, intermediateSteps: -5)

        // down + 1 interpolated drag + settle drag + up.
        #expect(zero.count == 4)
        #expect(negative.count == 4)
    }

    /// Every event of an on-bar gesture shares the caller-pinned vertical
    /// coordinate. This is the invariant that keeps Control Center reading a
    /// reorder: a path that dips below the bar is read as a removal, which is
    /// what orphaned a hosted item's scene in the field.
    @Test("A gesture pinned to one bar line keeps every event on that line")
    func gestureStaysOnTheBarLine() {
        let barY: CGFloat = 16.5
        let start = CGPoint(x: 1452, y: barY)
        let end = CGPoint(x: -3725, y: barY)

        let steps = Gesture.faithfulDrag(start: start, end: end, intermediateSteps: 4)

        #expect(steps.allSatisfy { $0.point.y == barY })
    }

    /// The interpolated drag points march monotonically from the press toward
    /// the destination and never overshoot either endpoint, so the drag reads
    /// as one continuous sweep.
    @Test("Interpolated points advance monotonically and stay between the endpoints")
    func interpolatedPointsAreMonotonic() {
        let start = CGPoint(x: 1452, y: 16.5)
        let end = CGPoint(x: -3725, y: 16.5)

        let steps = Gesture.faithfulDrag(start: start, end: end, intermediateSteps: 5)
        // The release intentionally repeats the destination occupied by the
        // settling drag, so monotonicity applies through the final drag rather
        // than across the stationary mouse-up event.
        let xs = steps.dropLast().map(\.point.x)

        // Strictly decreasing overall (start.x > end.x here).
        #expect(zip(xs, xs.dropFirst()).allSatisfy { $0 > $1 })
        let lowerBound = min(start.x, end.x)
        let upperBound = max(start.x, end.x)
        #expect(steps.allSatisfy { $0.point.x >= lowerBound && $0.point.x <= upperBound })
    }

    /// A rightward move (destination to the right of the item) advances the
    /// other way, confirming the builder is direction-agnostic.
    @Test("A rightward move advances left to right")
    func rightwardMoveAdvances() {
        let start = CGPoint(x: 200, y: 16.5)
        let end = CGPoint(x: 1000, y: 16.5)

        let steps = Gesture.faithfulDrag(start: start, end: end, intermediateSteps: 3)
        let xs = steps.dropLast().map(\.point.x)

        #expect(zip(xs, xs.dropFirst()).allSatisfy { $0 < $1 })
    }

    // MARK: Transport safety

    @Test("Horizontal paths distinguish safe segments, notch crossings, and invalid endpoints")
    func horizontalPathClassification() {
        let display: ClosedRange<CGFloat> = 0 ... 1470
        let notch: ClosedRange<CGFloat> = 645 ... 825

        #expect(MenuBarItemManager.horizontalPathDisposition(
            sourceX: 100,
            destinationX: 600,
            displayXRange: display,
            reservedNotchXRange: notch
        ) == .sameSafeSegment)
        #expect(MenuBarItemManager.horizontalPathDisposition(
            sourceX: 900,
            destinationX: 1400,
            displayXRange: display,
            reservedNotchXRange: notch
        ) == .sameSafeSegment)
        #expect(MenuBarItemManager.horizontalPathDisposition(
            sourceX: 600,
            destinationX: 900,
            displayXRange: display,
            reservedNotchXRange: notch
        ) == .crossesNotch)
        #expect(MenuBarItemManager.horizontalPathDisposition(
            sourceX: 700,
            destinationX: 900,
            displayXRange: display,
            reservedNotchXRange: notch
        ) == .invalidEndpoint)
        #expect(MenuBarItemManager.horizontalPathDisposition(
            sourceX: -1,
            destinationX: 900,
            displayXRange: display,
            reservedNotchXRange: notch
        ) == .invalidEndpoint)
    }

    @Test("Faithful dragging is selected only for one safe on-screen segment")
    func faithfulTransportSelection() {
        let selected: CGDirectDisplayID = 1
        #expect(MenuBarItemManager.strictTransportDecision(
            faithfulDragEnabled: true,
            itemIsControlItem: false,
            sourceDisplayID: selected,
            destinationDisplayID: selected,
            selectedDisplayID: selected,
            horizontalPath: .sameSafeSegment
        ) == .use(.faithfulDrag))
        #expect(MenuBarItemManager.strictTransportDecision(
            faithfulDragEnabled: false,
            itemIsControlItem: false,
            sourceDisplayID: selected,
            destinationDisplayID: selected,
            selectedDisplayID: selected,
            horizontalPath: .sameSafeSegment
        ) == .use(.teleport))
        #expect(MenuBarItemManager.strictTransportDecision(
            faithfulDragEnabled: true,
            itemIsControlItem: true,
            sourceDisplayID: selected,
            destinationDisplayID: selected,
            selectedDisplayID: selected,
            horizontalPath: .sameSafeSegment
        ) == .use(.teleport))
    }

    @Test("Parked and cross-notch teleports are explicit decisions")
    func explicitTeleportSelection() {
        let selected: CGDirectDisplayID = 1
        #expect(MenuBarItemManager.strictTransportDecision(
            faithfulDragEnabled: true,
            itemIsControlItem: false,
            sourceDisplayID: nil,
            destinationDisplayID: selected,
            selectedDisplayID: selected,
            horizontalPath: .invalidEndpoint
        ) == .use(.parkedTeleport))
        #expect(MenuBarItemManager.strictTransportDecision(
            faithfulDragEnabled: true,
            itemIsControlItem: false,
            sourceDisplayID: selected,
            destinationDisplayID: selected,
            selectedDisplayID: selected,
            horizontalPath: .crossesNotch
        ) == .use(.crossNotchTeleport))
    }

    @Test("Cross-display and invalid on-screen paths are rejected")
    func unsafeTransportIsRejected() {
        let selected: CGDirectDisplayID = 1
        let other: CGDirectDisplayID = 2
        #expect(MenuBarItemManager.strictTransportDecision(
            faithfulDragEnabled: true,
            itemIsControlItem: false,
            sourceDisplayID: selected,
            destinationDisplayID: other,
            selectedDisplayID: selected,
            horizontalPath: .sameSafeSegment
        ) == .rejectUnsafePath)
        #expect(MenuBarItemManager.strictTransportDecision(
            faithfulDragEnabled: true,
            itemIsControlItem: false,
            sourceDisplayID: selected,
            destinationDisplayID: selected,
            selectedDisplayID: selected,
            horizontalPath: .invalidEndpoint
        ) == .rejectUnsafePath)
    }

    @Test("A cross-notch teleport posts no intermediate center coordinate")
    func crossNotchTeleportUsesExactDestination() {
        let destination = CGPoint(x: 1200, y: 0)
        let locations = MenuBarItemManager.moveEventLocations(
            targetPoints: (start: destination, end: destination),
            faithfulDragStart: nil
        )

        #expect(locations.press == destination)
        #expect(locations.release == destination)
        #expect(locations.press.x != 735)
    }
}
