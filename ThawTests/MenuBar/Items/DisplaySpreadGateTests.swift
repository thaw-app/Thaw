//
//  DisplaySpreadGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

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
@Suite("Display spread gate")
struct DisplaySpreadGateTests {
    private let main = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let above = CGRect(x: 0, y: -1440, width: 2560, height: 1440)

    /// A single connected display can never spread; the predicate must short
    /// circuit so single-display users never defer.
    @Test("A single connected screen never reads as a spread")
    func singleScreenNeverSpreads() {
        #expect(
            !LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: 800, y: 10), CGPoint(x: 1200, y: 10)],
                screenFrames: [main]
            )
        )
    }

    /// Two displays connected, but every item resolves to the same screen: a
    /// settled layout. Must not defer.
    @Test("Every item on one of two screens is a settled layout")
    func allItemsOnOneOfTwoScreensDoesNotSpread() {
        #expect(
            !LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: 800, y: 10), CGPoint(x: 1200, y: 10)],
                screenFrames: [main, above]
            )
        )
    }

    /// Items straddle both displays: the relocation-in-progress state from the
    /// field log. This is the condition both gates must catch. Red against the
    /// missing predicate.
    @Test("Items split across two screens read as a spread")
    func itemsSplitAcrossTwoScreensSpreads() {
        #expect(
            LayoutSolver.itemsSpanMultipleDisplays(
                itemCenters: [CGPoint(x: 800, y: 10), CGPoint(x: 1000, y: -1065)],
                screenFrames: [main, above]
            )
        )
    }

    /// Items on one screen plus parked hidden items that happen to land on no
    /// display at all, because no screen occupies that coordinate range. The
    /// unmatched points must be ignored so a normal hidden layout does not read
    /// as spread. Note this is the lucky arrangement: see
    /// parkedItemInsideLeftDisplayReadsAsSpread for the case where a screen
    /// does own the parked coordinates.
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

    /// Two real on-screen items, one per display, mixed with parked items:
    /// still a spread (the parked items neither add nor mask the split).
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

    // The arrangement from the field log: an ultrawide main display with a
    // second screen to its right and a third to its left. The left screen owns
    // the negative x range that parked hidden items are shoved into, so the
    // "parked items land on no display" assumption the rest of this suite was
    // written against does not hold here.

    private let fieldMain = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    private let fieldRight = CGRect(x: 3440, y: 0, width: 2560, height: 1440)
    private let fieldLeft = CGRect(x: -2560, y: 0, width: 2560, height: 1440)

    private var fieldScreens: [CGRect] {
        [fieldMain, fieldRight, fieldLeft]
    }

    /// A parked hidden item shoved to x ≈ -2450 lands inside the left display,
    /// so the predicate honestly reports a spread. This is not a bug in the
    /// predicate; it is why callers must exclude parked items before calling
    /// it. Feeding every section in made both gates fire forever: the persist
    /// gate then blocked every write to savedSectionOrder, the saved layout
    /// stopped tracking the user's arrangement, and each window-ID change
    /// re-imposed the stale order.
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

    /// The same settled arrangement with the parked items excluded, which is
    /// what the callers now pass. Must not defer.
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
