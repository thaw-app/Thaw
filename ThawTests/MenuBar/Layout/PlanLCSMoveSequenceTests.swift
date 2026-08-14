//
//  PlanLCSMoveSequenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterization tests for LayoutSolver.planLCSMoveSequence.
///
/// Pins down the LCS-anchored move ordering used by applyProfileLayout's
/// Phase 2: identify items that must move, then for each select a stable
/// anchor (LCS item or already-moved item) in the same section, scanning
/// forward then backward, falling back to the section boundary.
@Suite("Plan LCS move sequence")
struct PlanLCSMoveSequenceTests {
    // MARK: - Scenarios

    /// When currentNoControls is empty, every entry in desiredNoControls
    /// is filtered out at the overlap step because
    /// LayoutSolver.planLCSMoveSequence only considers items present in
    /// both inputs, so the planner returns zero moves rather than
    /// attempting to place items it has not observed.
    @Test("An empty current layout produces no moves")
    func emptyCurrentProducesNoMovesDueToFilter() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: [],
            desiredNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result.isEmpty,
                "items missing from currentNoControls are filtered out before LCS work, so no moves are produced")
    }

    /// Identical current and desired produce zero planned moves.
    @Test("An already-matching layout produces no moves")
    func identicalCurrentAndDesiredNoMoves() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result == [])
    }

    /// One item swapped: only that item needs to move. The planner
    /// chooses an anchor among the LCS-stable items.
    @Test("A single swap plans exactly one move against an LCS-stable anchor")
    func singleSwapPlansOneMove() {
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

        #expect(result.count == 1)
        #expect(result.first?.uid == "a")
        // Anchor scan forward from position 1: c at position 2 is in
        // LCS and same section → leftOfUID("c").
        #expect(result.first?.destination == .leftOfUID("c"))
    }

    /// LCS items are preserved across sections; an anchor must be in
    /// the same section as the moving item. Setup:
    ///   current=[v1, x], desired=[x, v1, h1].
    /// After filtering to overlap, lcsCurrent=[v1,x] and lcsDesired=[x,v1]
    /// (h1 is in desired but not current). The LCS tie-break returns {x},
    /// so v1 is the item to move; the only same-section anchor (x) sits
    /// to its left, producing .rightOfUID(x).
    @Test("The anchor scan stays inside the moving item's section")
    func anchorScanRespectsSectionBoundary() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["v1", "x"],
            desiredNoControls: ["x", "v1", "h1"],
            sectionMap: ["v1": "visible", "x": "visible", "h1": "hidden"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "v1")
        #expect(result.first?.destination == .rightOfUID("x"))
    }

    /// Forward scan is preferred over backward scan; the planner picks
    /// the nearest forward stable anchor first.
    ///
    /// current=[b, a, c], desired=[a, b, c]. LCS={a,c}, so b moves.
    /// Position of b in desired is 1; forward scan finds c at 2 (LCS,
    /// same section) → .leftOfUID(c).
    @Test("The forward anchor scan is preferred over the backward one")
    func forwardScanPreferredOverBackward() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["b", "a", "c"],
            desiredNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "b")
        #expect(result.first?.destination == .leftOfUID("c"))
    }

    /// When no forward or backward anchor exists in the same section,
    /// the planner falls back to .sectionBoundary.
    ///
    /// current=[h1, x], desired=[x, h1]. LCS={x}, so h1 moves. h1's
    /// section is "hidden"; x's section is "visible". The backward scan
    /// stops immediately at the section boundary and no forward anchor
    /// exists. Result: .sectionBoundary(.hidden).
    @Test("With no same-section anchor the planner falls back to the section boundary")
    func sectionBoundaryFallbackWhenNoAnchorInSection() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["h1", "x"],
            desiredNoControls: ["x", "h1"],
            sectionMap: ["h1": "hidden", "x": "visible"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "h1")
        if case let .sectionBoundary(section) = result.first?.destination {
            #expect(section == .hidden)
        } else {
            Issue.record("expected .sectionBoundary(.hidden), got \(String(describing: result.first?.destination))")
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
    @Test("An already-moved item becomes a stable anchor for later moves")
    func alreadyMovedItemBecomesStableAnchor() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["c", "b", "a"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result.count == 2)
        #expect(result[0].uid == "b")
        #expect(result[0].destination == .rightOfUID("c"))
        #expect(result[1].uid == "a")
        #expect(result[1].destination == .rightOfUID("b"))
    }

    // MARK: - Preferred movers

    /// #885's minimal shape. The new item and `b` are interchangeable in a
    /// length-two LCS, and the ordinary backtrack keeps the new item stable,
    /// needlessly moving the established item instead.
    @Test("An unmanaged arrival moves instead of an established item")
    func unmanagedArrivalIsPreferredMover() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "b", "new"],
            desiredNoControls: ["a", "new", "b"],
            sectionMap: ["a": "hidden", "b": "hidden", "new": "hidden"],
            preferredMoveUIDs: ["new"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "new")
        #expect(result.first?.destination == .leftOfUID("b"))
    }

    /// The weighting is only a tie-break. If the unmanaged item already sits
    /// correctly, it remains in the LCS and no move is invented.
    @Test("A correctly placed unmanaged item remains stable")
    func correctlyPlacedUnmanagedItemDoesNotMove() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "new", "b"],
            desiredNoControls: ["a", "new", "b"],
            sectionMap: ["a": "hidden", "b": "hidden", "new": "hidden"],
            preferredMoveUIDs: ["new"]
        )

        #expect(result.isEmpty)
    }

    /// Preferred movers only resolve ties between equally long subsequences.
    /// They must not trade one established move for two unmanaged moves.
    @Test("Preferred movers never shorten the LCS")
    func preferredMoversDoNotShortenLCS() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c", "n1", "n2"],
            desiredNoControls: ["a", "b", "n1", "n2", "c"],
            sectionMap: [
                "a": "hidden", "b": "hidden", "c": "hidden",
                "n1": "hidden", "n2": "hidden",
            ],
            preferredMoveUIDs: ["n1", "n2"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "c")
    }

    /// Existing callers pass no preferred set and retain the historical LCS
    /// tie-break, keeping the change local to unmanaged-arrival applies.
    @Test("Without preferred movers the historical tie-break is unchanged")
    func noPreferredMoversKeepsHistoricalTieBreak() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "b", "new"],
            desiredNoControls: ["a", "new", "b"],
            sectionMap: ["a": "hidden", "b": "hidden", "new": "hidden"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "b")
    }

    // MARK: - Unanchorable anchors

    /// Thaw's chevron stays in the sequence — its position within visible is
    /// part of the layout and is persisted — which also made it selectable
    /// as a move anchor. Anchoring a failing move on one of Thaw's own
    /// dividers is what walks it across the bar: the insertion lands on the
    /// wrong side, the ordinal check refuses it, and because the bar lays
    /// out right to left the divider is shoved further left on every attempt
    /// (#924, #927). A neighbouring app item is an equally good insertion
    /// point and costs nothing when the move goes wrong.
    @Test("A control item is not chosen as an anchor when an app item is available")
    func controlItemIsNotChosenAsAnchor() {
        // current: [a, chevron, b, c] → desired: [a, chevron, c, b]
        // `b` must move; scanning forward from its desired slot the first
        // stable candidate is `chevron` going backward, `nil` going forward.
        let sectionMap = ["a": "visible", "chevron": "visible", "b": "visible", "c": "visible"]
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "chevron", "b", "c"],
            desiredNoControls: ["a", "chevron", "c", "b"],
            sectionMap: sectionMap,
            unanchorableUIDs: ["chevron"]
        )

        for move in result {
            if case let .leftOfUID(uid) = move.destination {
                #expect(uid != "chevron", "planned a move anchored on the chevron")
            }
            if case let .rightOfUID(uid) = move.destination {
                #expect(uid != "chevron", "planned a move anchored on the chevron")
            }
        }
    }

    /// Barring the chevron must not bar the move itself: with no other
    /// stable item in the section the planner falls back to the section
    /// boundary rather than giving up.
    @Test("With no app-item anchor available the move falls back to the boundary")
    func fallsBackToBoundaryWhenOnlyControlItemRemains() {
        // Only the chevron is stable, and it is unanchorable.
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["chevron", "b"],
            desiredNoControls: ["b", "chevron"],
            sectionMap: ["chevron": "visible", "b": "visible"],
            unanchorableUIDs: ["chevron"]
        )

        #expect(!result.isEmpty, "the move must still be planned")
        for move in result {
            if case .sectionBoundary = move.destination {
                continue
            }
            if case let .leftOfUID(uid) = move.destination {
                #expect(uid != "chevron")
            }
            if case let .rightOfUID(uid) = move.destination {
                #expect(uid != "chevron")
            }
        }
    }

    /// Default argument keeps every existing caller and every existing
    /// expectation in this suite unchanged.
    @Test("With no unanchorable set the planner behaves exactly as before")
    func emptyUnanchorableSetIsUnchanged() {
        let current = ["a", "b", "c"]
        let desired = ["b", "a", "c"]
        let map = ["a": "visible", "b": "visible", "c": "visible"]

        #expect(
            LayoutSolver.planLCSMoveSequence(
                currentNoControls: current, desiredNoControls: desired, sectionMap: map
            ) == LayoutSolver.planLCSMoveSequence(
                currentNoControls: current, desiredNoControls: desired, sectionMap: map,
                unanchorableUIDs: []
            )
        )
    }
}
