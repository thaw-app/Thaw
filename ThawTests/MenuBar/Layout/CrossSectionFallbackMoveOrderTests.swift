//
//  CrossSectionFallbackMoveOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Tests for LayoutSolver.crossSectionFallbackMoveOrder.
///
/// The fallback drags every item crossing the hidden/always-hidden boundary onto
/// the always-hidden divider, so each move displaces its predecessors and items
/// come to rest in reverse issue order.
///
/// A reversed run is quiet: sections, tallies, divider gates, and saved order
/// all read correct. With enforceConcealedSectionOrder off,
/// relaxConcealedSectionOrder then adopts the reversed order and the apply
/// reports success over a visibly backwards bar.
@Suite("Cross-section fallback move order")
struct CrossSectionFallbackMoveOrderTests {
    /// The last entry moves first and is pushed furthest right; index 0 moves last
    /// and rests beside the divider.
    @Test("Items bound for hidden move in reverse saved order")
    func hiddenBoundItemsMoveInReverseSavedOrder() {
        let order = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: ["a", "b", "c", "d"],
            crossing: ["a", "b", "c", "d"],
            landingSlot: .leftmostOfHidden
        )

        #expect(order == ["d", "c", "b", "a"])
    }

    /// The mirror image: index 0 moves first and is pushed furthest left.
    @Test("Items bound for always-hidden move in saved order")
    func alwaysHiddenBoundItemsMoveInSavedOrder() {
        let order = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: ["a", "b", "c", "d"],
            crossing: ["a", "b", "c", "d"],
            landingSlot: .rightmostOfAlwaysHidden
        )

        #expect(order == ["a", "b", "c", "d"])
    }

    /// Entries already on the correct side are skipped but still shape the relative order.
    @Test("Entries not crossing are skipped without disturbing the rest")
    func nonCrossingEntriesSkipped() {
        let order = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: ["a", "b", "c", "d", "e"],
            crossing: ["b", "d"],
            landingSlot: .leftmostOfHidden
        )

        #expect(order == ["d", "b"])
    }

    /// Unknown identifiers are appended so they land against the divider; sorted so
    /// Set iteration order cannot make two applies disagree.
    @Test("Unknown identifiers are appended in sorted order")
    func unknownIdentifiersAppendedSorted() {
        let order = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: ["a", "b"],
            crossing: ["a", "b", "z", "y"],
            landingSlot: .leftmostOfHidden
        )

        #expect(order == ["b", "a", "y", "z"])
    }

    /// The fast path where the AH_ctrl placement already split correctly must stay free.
    @Test("An empty crossing set issues no moves")
    func emptyCrossingSetIssuesNoMoves() {
        let order = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: ["a", "b", "c"],
            crossing: [],
            landingSlot: .rightmostOfAlwaysHidden
        )

        #expect(order.isEmpty)
    }

    /// Field log thaw_2026-08-27_09-14-14: four items crossing into hidden were
    /// issued in saved order and came to rest reversed:
    ///
    ///     saved:  Numi, Maccy, Flameshot, Hookshot, BetterDisplay, DisplayLink
    ///     result: DisplayLink, BetterDisplay, Hookshot, Maccy, Numi
    ///
    /// Flameshot was not running and Numi never crossed; where non-crossing items
    /// end up is decided by the AH_ctrl placement, so this asserts only the relative
    /// order of the items the fallback issues.
    @Test("Field regression: four items crossing into hidden are not reversed")
    func fieldRegressionItemsCrossingIntoHiddenAreNotReversed() {
        let savedHiddenOrder = [
            "com.dmitrynikolaev.numi:Item-0",
            "org.p0deje.Maccy:Item-0",
            "org.flameshot.Flameshot:Item-0",
            "com.knollsoft.Hookshot:Item-0",
            "pro.betterdisplay.BetterDisplay:Item-0",
            "com.displaylink.DisplayLinkUserAgent:Item-0",
        ]
        let crossing: Set = [
            "org.p0deje.Maccy:Item-0",
            "com.knollsoft.Hookshot:Item-0",
            "pro.betterdisplay.BetterDisplay:Item-0",
            "com.displaylink.DisplayLinkUserAgent:Item-0",
        ]

        let moveOrder = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: savedHiddenOrder,
            crossing: crossing,
            landingSlot: .leftmostOfHidden
        )

        #expect(moveOrder == [
            "com.displaylink.DisplayLinkUserAgent:Item-0",
            "pro.betterdisplay.BetterDisplay:Item-0",
            "com.knollsoft.Hookshot:Item-0",
            "org.p0deje.Maccy:Item-0",
        ])

        // Each move takes hidden's leftmost slot, so they rest in reverse issue order,
        // which is the saved order the field log did not show.
        #expect(Array(moveOrder.reversed()) == savedHiddenOrder.filter(crossing.contains))
    }
}
