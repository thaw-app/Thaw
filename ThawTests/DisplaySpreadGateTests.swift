//
//  DisplaySpreadGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterizes the display-spread predicate that both the saved-layout apply
/// and the section-order persist consult before acting.
///
/// When the active menu bar relocates to another display macOS migrates the
/// status item windows between screens asynchronously. For a window of time
/// the managed items straddle two displays: some still on the old screen,
/// some already on the new one. A bulk apply dispatched in that window
/// resolves each item's move against whichever display its window currently
/// occupies, so the moves cannot converge and leave items stranded on the
/// wrong screen, where they read as un-hidden. Persisting the section order in
/// that window bakes the transition artifact into the saved layout. Both
/// callers defer until the items collapse back onto a single display.
///
/// Frames are expressed in the global CoreGraphics coordinate space
/// (top-left origin), the same space the menu bar item bounds use, so a
/// secondary display positioned above the main one has a negative y origin.
final class DisplaySpreadGateTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let above = CGRect(x: 0, y: -1440, width: 2560, height: 1440)

    /// A single connected display can never spread; the predicate must short
    /// circuit so single-display users never defer.
    func testSingleScreenNeverSpreads() {
        XCTAssertFalse(
            LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: 800, y: 10), CGPoint(x: 1200, y: 10)],
                screenFrames: [main]
            )
        )
    }

    /// Two displays connected, but every item resolves to the same screen: a
    /// settled layout. Must not defer.
    func testAllItemsOnOneOfTwoScreensDoesNotSpread() {
        XCTAssertFalse(
            LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: 800, y: 10), CGPoint(x: 1200, y: 10)],
                screenFrames: [main, above]
            )
        )
    }

    /// Items straddle both displays: the relocation-in-progress state from the
    /// field log. This is the condition both gates must catch. Red against the
    /// missing predicate.
    func testItemsSplitAcrossTwoScreensSpreads() {
        XCTAssertTrue(
            LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: 800, y: 10), CGPoint(x: 1000, y: -1065)],
                screenFrames: [main, above]
            )
        )
    }

    /// Items on one screen plus intentionally off-screen parked hidden items
    /// (the control item shoves them ~10000px left, onto no display). The
    /// parked points must be ignored so a normal hidden layout does not read
    /// as spread.
    func testOffScreenParkedItemsAreIgnored() {
        XCTAssertFalse(
            LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [
                    CGPoint(x: 800, y: 10),
                    CGPoint(x: 1200, y: 10),
                    CGPoint(x: -7535, y: -1065), // parked hidden control item
                    CGPoint(x: -10071, y: -1065), // parked hidden item
                ],
                screenFrames: [main, above]
            )
        )
    }

    /// Only parked off-screen items resolve to no display at all: not a spread.
    func testOnlyOffScreenItemsDoesNotSpread() {
        XCTAssertFalse(
            LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: -7535, y: -1065), CGPoint(x: -10071, y: -1065)],
                screenFrames: [main, above]
            )
        )
    }

    /// Two real on-screen items, one per display, mixed with parked items:
    /// still a spread (the parked items neither add nor mask the split).
    func testSplitWithParkedItemsStillSpreads() {
        XCTAssertTrue(
            LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [
                    CGPoint(x: 800, y: 10), // display 1
                    CGPoint(x: 1000, y: -1065), // display 2
                    CGPoint(x: -7535, y: -1065), // parked
                ],
                screenFrames: [main, above]
            )
        )
    }

    /// No items at all: nothing to spread.
    func testEmptyItemsDoesNotSpread() {
        XCTAssertFalse(
            LayoutSolver.itemsSpanMultipleDisplays(itemCenters: [], screenFrames: [main, above])
        )
    }
}
