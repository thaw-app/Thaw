//
//  PlanLCSMoveSequenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterization tests for LayoutSolver.planLCSMoveSequence.
///
/// Pins down the LCS-anchored move ordering used by applyProfileLayout's
/// Phase 2: identify items that must move, then for each select a stable
/// anchor (LCS item or already-moved item) in the same section, scanning
/// forward then backward, falling back to the section boundary.
final class PlanLCSMoveSequenceTests: XCTestCase {
    // MARK: - Scenarios

    /// When currentNoControls is empty, every entry in desiredNoControls
    /// is filtered out at the overlap step because
    /// LayoutSolver.planLCSMoveSequence only considers items present in
    /// both inputs, so the planner returns zero moves rather than
    /// attempting to place items it has not observed.
    func testEmptyCurrentProducesNoMovesDueToFilter() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: [],
            desiredNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        XCTAssertEqual(result.count, 0,
                       "items missing from currentNoControls are filtered out before LCS work, so no moves are produced")
    }

    /// Identical current and desired produce zero planned moves.
    func testIdenticalCurrentAndDesiredNoMoves() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        XCTAssertEqual(result, [])
    }

    /// One item swapped: only that item needs to move. The planner
    /// chooses an anchor among the LCS-stable items.
    func testSingleSwapPlansOneMove() {
        // current: [a, b, c]  → desired: [b, a, c]
        // Common subsequences:
        //   {a,c} (length 2) — keeps a and c in place.
        //   {b,c} (length 2) — keeps b and c.
        // The LCS function returns one of the equal-length subsequences
        // deterministically based on the backtrack tie-break. With
        // dp[i-1][j] > dp[i][j-1] preferring i-1, the result is {b,c}.
        // Therefore a is the item to move.
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["b", "a", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.uid, "a")
        // Anchor scan forward from position 1: c at position 2 is in
        // LCS and same section → leftOfUID("c").
        XCTAssertEqual(result.first?.destination, .leftOfUID("c"))
    }

    /// LCS items are preserved across sections; an anchor must be in
    /// the same section as the moving item. Setup:
    ///   current=[v1, x], desired=[x, v1, h1].
    /// After filtering to overlap, lcsCurrent=[v1,x] and lcsDesired=[x,v1]
    /// (h1 is in desired but not current). The LCS tie-break returns {x},
    /// so v1 is the item to move; the only same-section anchor (x) sits
    /// to its left, producing .rightOfUID(x).
    func testAnchorScanRespectsSectionBoundary() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["v1", "x"],
            desiredNoControls: ["x", "v1", "h1"],
            sectionMap: ["v1": "visible", "x": "visible", "h1": "hidden"]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.uid, "v1")
        XCTAssertEqual(result.first?.destination, .rightOfUID("x"))
    }

    /// Forward scan is preferred over backward scan; the planner picks
    /// the nearest forward stable anchor first.
    ///
    /// current=[b, a, c], desired=[a, b, c]. LCS={a,c}, so b moves.
    /// Position of b in desired is 1; forward scan finds c at 2 (LCS,
    /// same section) → .leftOfUID(c).
    func testForwardScanPreferredOverBackward() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["b", "a", "c"],
            desiredNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.uid, "b")
        XCTAssertEqual(result.first?.destination, .leftOfUID("c"))
    }

    /// When no forward or backward anchor exists in the same section,
    /// the planner falls back to .sectionBoundary.
    ///
    /// current=[h1, x], desired=[x, h1]. LCS={x}, so h1 moves. h1's
    /// section is "hidden"; x's section is "visible". The backward scan
    /// stops immediately at the section boundary and no forward anchor
    /// exists. Result: .sectionBoundary(.hidden).
    func testSectionBoundaryFallbackWhenNoAnchorInSection() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["h1", "x"],
            desiredNoControls: ["x", "h1"],
            sectionMap: ["h1": "hidden", "x": "visible"]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.uid, "h1")
        if case let .sectionBoundary(section) = result.first?.destination {
            XCTAssertEqual(section, .hidden)
        } else {
            XCTFail("expected .sectionBoundary(.hidden), got \(String(describing: result.first?.destination))")
        }
    }

    /// An item already moved in the planning sequence becomes a stable
    /// anchor for subsequent items.
    ///
    /// current=[a, b, c], desired=[c, b, a]. LCS={c}, so b and a move
    /// (in lcsDesired order: b at index 1, then a at index 2).
    /// - b at desired idx 1: forward scan finds a (not yet moved) → skip.
    ///   Backward scan finds c at idx 0 (in LCS, same section) → .rightOfUID(c).
    /// - a at desired idx 2: backward scan finds b at idx 1 (now in
    ///   movedItems, same section) → .rightOfUID(b).
    func testAlreadyMovedItemBecomesStableAnchor() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["c", "b", "a"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].uid, "b")
        XCTAssertEqual(result[0].destination, .rightOfUID("c"))
        XCTAssertEqual(result[1].uid, "a")
        XCTAssertEqual(result[1].destination, .rightOfUID("b"))
    }
}
