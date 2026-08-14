//
//  MouseHelpersCursorPointTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers `MouseHelpers.cursorPoint(overItemWithBounds:displayBounds:)`, the
/// point the search panel warps to after revealing an item.
///
/// The guard is the point of the helper: `CGWarpMouseCursorPosition` clamps a
/// point that lies on no display to the leftmost edge of one, which sits under
/// the Apple menu. Hidden and always-hidden items on a notched display sit at
/// negative X while they are offscreen, so a helper that answered with a point
/// unconditionally would drag the pointer under the Apple menu on exactly the
/// items this feature exists for.
@Suite("Cursor point over a revealed item")
struct MouseHelpersCursorPointTests {
    /// The built-in display, plus one to its left, in the global top-left
    /// origin coordinate space that `CGDisplayBounds` uses.
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
    /// rect, whose center is the origin — a point that a display containing
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
}
