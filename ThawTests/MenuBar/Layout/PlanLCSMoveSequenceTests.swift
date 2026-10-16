//
//  PlanLCSMoveSequenceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// LayoutSolver.planLCSMoveSequence: for each item that must move, pick a stable
/// same-section anchor (LCS or already-moved item), scanning forward then
/// backward, else the section boundary.
@Suite("Plan LCS move sequence")
struct PlanLCSMoveSequenceTests {
    // MARK: - Scenarios

    /// The planner only considers items present in both inputs, so it never places unobserved items.
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

    @Test("An already-matching layout produces no moves")
    func identicalCurrentAndDesiredNoMoves() {
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result == [])
    }

    @Test("A single swap plans exactly one move against an LCS-stable anchor")
    func singleSwapPlansOneMove() {
        // current [a, b, c], desired [b, a, c]: {a,c} and {b,c} tie at length 2.
        // The backtrack prefers dp[i-1][j], giving {b,c}, so a moves.
        let result = LayoutSolver.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["b", "a", "c"],
            sectionMap: ["a": "visible", "b": "visible", "c": "visible"]
        )

        #expect(result.count == 1)
        #expect(result.first?.uid == "a")
        // Forward from position 1, c is in the LCS and same section.
        #expect(result.first?.destination == .leftOfUID("c"))
    }

    /// current=[v1, x], desired=[x, v1, h1]. The tie-break keeps {x}, so v1 moves,
    /// and its only same-section anchor x sits to its left: `.rightOfUID(x)`.
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

    /// current=[b, a, c], desired=[a, b, c]. LCS={a,c}, so b moves; forward scan
    /// finds c first: `.leftOfUID(c)`.
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

    /// current=[h1, x], desired=[x, h1]. LCS={x}; h1 is hidden and x visible, so
    /// neither scan finds an anchor: `.sectionBoundary(.hidden)`.
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

    /// current=[a, b, c], desired=[c, b, a]. LCS={c}, so b then a move.
    /// - b: forward finds unmoved a, backward finds c: `.rightOfUID(c)`.
    /// - a: backward finds the now-moved b: `.rightOfUID(b)`.
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

    /// The new item and `b` tie in a length-two LCS, and the plain backtrack keeps
    /// the new item, moving the established one instead (#885).
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

    /// Only a tie-break: a correctly placed unmanaged item stays in the LCS.
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

    /// Never trade one established move for two unmanaged moves.
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

    /// Callers without a preferred set keep the historical tie-break.
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

    /// The chevron stays in the sequence because its position is persisted, which
    /// made it an anchor. A failing move anchored on a divider shoves it further
    /// left each attempt (#924, #927); a neighbouring app item costs nothing.
    @Test("A control item is not chosen as an anchor when an app item is available")
    func controlItemIsNotChosenAsAnchor() {
        // current [a, chevron, b, c], desired [a, chevron, c, b]: b moves, and the
        // only stable candidate is the chevron behind it.
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

    /// Barring the chevron falls back to the section boundary instead of giving up.
    @Test("With no app-item anchor available the move falls back to the boundary")
    func fallsBackToBoundaryWhenOnlyControlItemRemains() {
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
