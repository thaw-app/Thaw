//
//  DisplaySpreadGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes the display-spread predicate that both the saved-layout apply
/// and the section-order persist consult before acting.
///
/// When the menu bar moves to another display, macOS migrates status item
/// windows asynchronously, so items briefly straddle two screens. Applying or
/// persisting then strands items or bakes the transition into the saved
/// layout, so both callers defer until items settle on one display.
///
/// Frames use global CoreGraphics coordinates (top-left origin), so a display
/// above the main one has a negative y origin.
@Suite("Display spread gate")
struct DisplaySpreadGateTests {
    private let main = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let above = CGRect(x: 0, y: -1440, width: 2560, height: 1440)

    /// Single-display users must never defer.
    @Test("A single connected screen never reads as a spread")
    func singleScreenNeverSpreads() {
        #expect(
            !LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: 800, y: 10), CGPoint(x: 1200, y: 10)],
                screenFrames: [main]
            )
        )
    }

    /// Every item on the same one of two screens is settled and must not defer.
    @Test("Every item on one of two screens is a settled layout")
    func allItemsOnOneOfTwoScreensDoesNotSpread() {
        #expect(
            !LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: 800, y: 10), CGPoint(x: 1200, y: 10)],
                screenFrames: [main, above]
            )
        )
    }

    /// Items straddling both displays is the relocation state both gates must catch.
    @Test("Items split across two screens read as a spread")
    func itemsSplitAcrossTwoScreensSpreads() {
        #expect(
            LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: 800, y: 10), CGPoint(x: 1000, y: -1065)],
                screenFrames: [main, above]
            )
        )
    }

    /// Parked hidden items that land on no display must be ignored. See
    /// parkedItemInsideLeftDisplayReadsAsSpread for when a screen owns them.
    @Test("Parked off-screen items are ignored")
    func offScreenParkedItemsAreIgnored() {
        #expect(
            !LayoutSolver.itemsSpanMultipleDisplays(
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
    @Test("Only parked off-screen items is not a spread")
    func onlyOffScreenItemsDoesNotSpread() {
        #expect(
            !LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: -7535, y: -1065), CGPoint(x: -10071, y: -1065)],
                screenFrames: [main, above]
            )
        )
    }

    /// Parked items neither add to nor mask a real split.
    @Test("A split mixed with parked items is still a spread")
    func splitWithParkedItemsStillSpreads() {
        #expect(
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
    @Test("No items at all is not a spread")
    func emptyItemsDoesNotSpread() {
        #expect(
            !LayoutSolver.itemsSpanMultipleDisplays(itemCenters: [], screenFrames: [main, above])
        )
    }

    // MARK: - Displays to the left of the main one

    // Ultrawide main display with screens to its right and left. The left
    // screen owns the negative x range parked hidden items are shoved into.

    private let fieldMain = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    private let fieldRight = CGRect(x: 3440, y: 0, width: 2560, height: 1440)
    private let fieldLeft = CGRect(x: -2560, y: 0, width: 2560, height: 1440)

    private var fieldScreens: [CGRect] {
        [fieldMain, fieldRight, fieldLeft]
    }

    /// A parked item at x ≈ -2450 lands inside the left display and reads as
    /// a spread, so callers must exclude parked items. Otherwise both gates
    /// fire forever and savedSectionOrder is never written.
    @Test("A parked item inside a left-positioned display reads as a spread")
    func parkedItemInsideLeftDisplayReadsAsSpread() {
        #expect(
            LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [
                    CGPoint(x: 2846, y: 15), // visible item on the main display
                    CGPoint(x: -2450, y: 15), // parked hidden item, inside fieldLeft
                ],
                screenFrames: fieldScreens
            )
        )
    }

    /// With parked items excluded, as callers pass them, this must not defer.
    @Test("Unparked centers alone do not spread on a left-positioned arrangement")
    func unparkedCentersDoNotSpreadOnFieldArrangement() {
        #expect(
            !LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [
                    CGPoint(x: 2846, y: 15),
                    CGPoint(x: 3201, y: 15),
                    CGPoint(x: 3247, y: 15),
                ],
                screenFrames: fieldScreens
            )
        )
    }

    /// A real relocation still has to be caught on this arrangement: the
    /// unparked items themselves straddle the main and right displays.
    @Test("A relocation across a left-positioned arrangement is still a spread")
    func relocationStillSpreadsOnFieldArrangement() {
        #expect(
            LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [
                    CGPoint(x: 2846, y: 15), // still on the main display
                    CGPoint(x: 4200, y: 15), // already migrated to the right display
                ],
                screenFrames: fieldScreens
            )
        )
    }
}
