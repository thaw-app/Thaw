//
//  MouseHelpersCursorPointTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers MouseHelpers.cursorPoint(overItemWithBounds:displayBounds:), the
/// point the search panel warps to after revealing an item.
///
/// The guard is the point of the helper: CGWarpMouseCursorPosition clamps a
/// point that lies on no display to the leftmost edge of one, which sits under
/// the Apple menu. Hidden and always-hidden items on a notched display sit at
/// negative X while they are offscreen, so a helper that answered with a point
/// unconditionally would drag the pointer under the Apple menu on exactly the
/// items this feature exists for.
@Suite("Cursor point over a revealed item")
struct MouseHelpersCursorPointTests {
    /// The built-in display, plus one to its left, in the global top-left
    /// origin coordinate space that CGDisplayBounds uses.
    private let displays = [
        CGRect(x: 0, y: 0, width: 1800, height: 1169),
        CGRect(x: -1920, y: 0, width: 1920, height: 1080),
    ]

    @Test("An item on a display resolves to its center")
    func itemOnDisplayResolvesToCenter() {
        let bounds = CGRect(x: 1500, y: 0, width: 30, height: 24)

        let point = MouseHelpers.cursorPoint(overItemWithBounds: bounds, displayBounds: displays)

        #expect(point == CGPoint(x: 1515, y: 12))
    }

    @Test("An item on a secondary display resolves to its center")
    func itemOnSecondaryDisplayResolvesToCenter() {
        let bounds = CGRect(x: -500, y: 0, width: 30, height: 24)

        let point = MouseHelpers.cursorPoint(overItemWithBounds: bounds, displayBounds: displays)

        #expect(point == CGPoint(x: -485, y: 12))
    }

    /// The offscreen parking spot Thaw uses for items it has hidden.
    @Test("An offscreen item resolves to no point")
    func offscreenItemResolvesToNoPoint() {
        let bounds = CGRect(x: -25000, y: 0, width: 30, height: 24)

        let point = MouseHelpers.cursorPoint(overItemWithBounds: bounds, displayBounds: displays)

        #expect(point == nil)
    }

    @Test("An item below the displays resolves to no point")
    func itemBelowDisplaysResolvesToNoPoint() {
        let bounds = CGRect(x: 1500, y: 2000, width: 30, height: 24)

        let point = MouseHelpers.cursorPoint(overItemWithBounds: bounds, displayBounds: displays)

        #expect(point == nil)
    }

    /// An item whose window has already gone away reads back as an empty
    /// rect, whose center is the origin, a point that a display containing
    /// the origin would otherwise accept.
    @Test("Empty bounds resolve to no point", arguments: [
        CGRect.zero,
        CGRect(x: 40, y: 0, width: 0, height: 24),
        CGRect(x: 40, y: 0, width: 30, height: 0),
    ])
    func emptyBoundsResolveToNoPoint(bounds: CGRect) {
        let point = MouseHelpers.cursorPoint(overItemWithBounds: bounds, displayBounds: displays)

        #expect(point == nil)
    }

    @Test("With no displays every item resolves to no point")
    func noDisplaysResolveToNoPoint() {
        let bounds = CGRect(x: 1500, y: 0, width: 30, height: 24)

        let point = MouseHelpers.cursorPoint(overItemWithBounds: bounds, displayBounds: [])

        #expect(point == nil)
    }

    @Test("Saved cursor position is restored only while Thaw retains ownership")
    func cursorRestorationRespectsPhysicalInput() {
        #expect(MouseHelpers.shouldRestoreSavedCursorPosition(
            physicalPointerInputOccurred: false
        ))
        #expect(!MouseHelpers.shouldRestoreSavedCursorPosition(
            physicalPointerInputOccurred: true
        ))
    }

    /// The parked teleport from #318: press and release at x -3751, behind the
    /// collapsed hidden divider, which no display contains.
    @Test("A parked press point lies off every display")
    func parkedPressPointIsOffEveryDisplay() {
        #expect(MouseHelpers.isOffEveryDisplay(
            CGPoint(x: -3751, y: 15),
            displayBounds: displays
        ))
    }

    @Test("A point on the bar of either display is on a display")
    func onBarPointsAreOnADisplay() {
        #expect(!MouseHelpers.isOffEveryDisplay(CGPoint(x: 1505, y: 15), displayBounds: displays))
        #expect(!MouseHelpers.isOffEveryDisplay(CGPoint(x: -100, y: 15), displayBounds: displays))
    }

    @Test("With no displays known, every point counts as off-display")
    func noDisplaysMeansOffEveryDisplay() {
        #expect(MouseHelpers.isOffEveryDisplay(CGPoint(x: 10, y: 10), displayBounds: []))
    }

    /// #318: the user moved the mouse during a 127 ms rehide, so the old rule
    /// kept the cursor where the parked press had clamped it, under the Apple menu.
    @Test("An event posted off every display is undone even after physical input")
    func offDisplayEventsAreRestoredDespitePhysicalInput() {
        #expect(MouseHelpers.shouldRestoreSavedCursorPosition(
            physicalPointerInputOccurred: true,
            postedEventsOffEveryDisplay: true
        ))
        #expect(MouseHelpers.shouldRestoreSavedCursorPosition(
            physicalPointerInputOccurred: false,
            postedEventsOffEveryDisplay: true
        ))
    }

    @Test("On-screen moves still respect the user's own movement")
    func onScreenMovesKeepPhysicalInputRule() {
        #expect(!MouseHelpers.shouldRestoreSavedCursorPosition(
            physicalPointerInputOccurred: true,
            postedEventsOffEveryDisplay: false
        ))
        #expect(MouseHelpers.shouldRestoreSavedCursorPosition(
            physicalPointerInputOccurred: false,
            postedEventsOffEveryDisplay: false
        ))
    }

    /// Frontmost-app triggers move without hiding the cursor. They leave an
    /// on-screen warp alone, as before, but must undo an off-display event.
    @Test("A move without cursor ownership restores only after off-display events")
    func moveWithoutOwnershipRestoresOnlyOffDisplay() {
        #expect(!MouseHelpers.shouldRestoreSavedCursorPosition(
            physicalPointerInputOccurred: false,
            postedEventsOffEveryDisplay: false,
            tookCursorOwnership: false
        ))
        #expect(MouseHelpers.shouldRestoreSavedCursorPosition(
            physicalPointerInputOccurred: true,
            postedEventsOffEveryDisplay: true,
            tookCursorOwnership: false
        ))
    }
}
