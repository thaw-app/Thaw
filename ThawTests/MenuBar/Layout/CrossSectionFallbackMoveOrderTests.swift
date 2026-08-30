//
//  CrossSectionFallbackMoveOrderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Tests for LayoutSolver.crossSectionFallbackMoveOrder.
///
/// The per-item fallback in applyProfileLayout drags every item that still
/// needs to cross the hidden to always-hidden boundary onto one anchor, the
/// always-hidden divider. The landing slot is therefore the same for every
/// move in the run, and each move displaces its predecessors one place
/// further from the divider. The order the moves are issued in is the order
/// the items come to rest in, reversed.
///
/// The failure this locks down is quiet. A reversed run leaves every item in
/// the section the profile asked for, so the cross-section tallies, the
/// divider gates and the saved order all read as correct; only the order the
/// user sees when the section is revealed is backwards. With
/// enforceConcealedSectionOrder off, relaxConcealedSectionOrder then rewrites
/// the desired sequence to match, so the LCS plans nothing and the apply
/// reports success over a visibly backwards bar.
@Suite("Cross-section fallback move order")
struct CrossSectionFallbackMoveOrderTests {
    /// Landing at the leftmost slot of hidden means the saved order has to
    /// be issued back-to-front: the last entry moves first and is pushed
    /// furthest right, index 0 moves last and comes to rest adjacent to the
    /// divider, which is where left-to-right index 0 belongs.
    @Test("Items bound for hidden move in reverse saved order")
    func hiddenBoundItemsMoveInReverseSavedOrder() {
        let order = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: ["a", "b", "c", "d"],
            crossing: ["a", "b", "c", "d"],
            landingSlot: .leftmostOfHidden
        )

        #expect(order == ["d", "c", "b", "a"])
    }

    /// Landing at the rightmost slot of always-hidden is the mirror image:
    /// index 0 moves first and is pushed furthest left, which is where
    /// left-to-right index 0 belongs.
    @Test("Items bound for always-hidden move in saved order")
    func alwaysHiddenBoundItemsMoveInSavedOrder() {
        let order = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: ["a", "b", "c", "d"],
            crossing: ["a", "b", "c", "d"],
            landingSlot: .rightmostOfAlwaysHidden
        )

        #expect(order == ["a", "b", "c", "d"])
    }

    /// Only the items actually crossing are issued. Entries the profile
    /// carries that are already on the correct side keep their influence on
    /// the relative order of the ones that are not.
    @Test("Entries not crossing are skipped without disturbing the rest")
    func nonCrossingEntriesSkipped() {
        let order = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: ["a", "b", "c", "d", "e"],
            crossing: ["b", "d"],
            landingSlot: .leftmostOfHidden
        )

        #expect(order == ["d", "b"])
    }

    /// An identifier the profile has no position for is appended, so it
    /// lands against the divider rather than displacing an item the profile
    /// does place. Sorted, so a Set's arbitrary iteration order cannot make
    /// two applies of the same profile disagree.
    @Test("Unknown identifiers are appended in sorted order")
    func unknownIdentifiersAppendedSorted() {
        let order = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: ["a", "b"],
            crossing: ["a", "b", "z", "y"],
            landingSlot: .leftmostOfHidden
        )

        #expect(order == ["b", "a", "y", "z"])
    }

    /// Nothing crossing plans nothing: the fast path where the AH_ctrl
    /// placement already produced the correct split must stay free.
    @Test("An empty crossing set issues no moves")
    func emptyCrossingSetIssuesNoMoves() {
        let order = LayoutSolver.crossSectionFallbackMoveOrder(
            profileOrder: ["a", "b", "c"],
            crossing: [],
            landingSlot: .rightmostOfAlwaysHidden
        )

        #expect(order.isEmpty)
    }

    /// Regression, reproduced from a field log (thaw_2026-08-27_09-14-14).
    ///
    /// Applying an all-in-always-hidden profile and then switching back left
    /// four items needing to cross into hidden. The fallback issued them in
    /// saved order (Maccy, Hookshot, BetterDisplay, DisplayLink), each to the
    /// right of AH_ctrl, and the bar came to rest exactly reversed:
    ///
    ///     saved:  Numi, Maccy, Flameshot, Hookshot, BetterDisplay, DisplayLink
    ///     result: DisplayLink, BetterDisplay, Hookshot, Maccy, Numi
    ///
    /// Flameshot was not running and never crossed. Numi did not cross
    /// either: the preceding AH_ctrl move landed left of it, which made it
    /// hidden's leftmost item, and the four then inserted to its left. Where
    /// a non-crossing item ends up relative to the run is decided by that
    /// divider placement, not here, so this asserts only what the fallback
    /// controls: the relative order of the items it issues.
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

        // The order the moves are issued in.
        #expect(moveOrder == [
            "com.displaylink.DisplayLinkUserAgent:Item-0",
            "pro.betterdisplay.BetterDisplay:Item-0",
            "com.knollsoft.Hookshot:Item-0",
            "org.p0deje.Maccy:Item-0",
        ])

        // The order they come to rest in. Each move takes the slot next to
        // the divider, the leftmost slot of hidden, and pushes its
        // predecessors right, so the run reads as the moves reversed. That
        // is the saved order, which is what the field log did not show.
        #expect(Array(moveOrder.reversed()) == savedHiddenOrder.filter(crossing.contains))
    }
}
