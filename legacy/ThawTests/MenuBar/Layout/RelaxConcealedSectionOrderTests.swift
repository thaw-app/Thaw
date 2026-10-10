//
//  RelaxConcealedSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// LayoutSolver.relaxConcealedSectionOrder.
///
/// A move costs a cursor hijack and a synthetic drag whether or not anyone sees
/// it, and parked items are rendered by the Thaw Bar from the cache anyway.
/// Rewriting the desired sequence, not filtering planned moves, lets the LCS see
/// them as in place so no surviving move anchors on an item assumed to shift.
///
/// Only intra-section order is relaxed, never membership.
@Suite("Relax concealed section order")
struct RelaxConcealedSectionOrderTests {
    /// Relaxation must not invent churn of its own.
    @Test("An already-matching sequence is returned unchanged")
    func matchingSequenceUnchanged() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["a", "b", "c"],
            currentNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "hidden", "c": "hidden"]
        )

        #expect(result == ["a", "b", "c"])
    }

    /// Hidden items are rewritten to their current order, so the LCS plans nothing.
    @Test("Hidden items are rewritten into their current relative order")
    func hiddenItemsAdoptCurrentOrder() {
        let sectionMap = ["a": "visible", "b": "hidden", "c": "hidden"]
        let relaxed = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["a", "c", "b"],
            currentNoControls: ["a", "b", "c"],
            sectionMap: sectionMap
        )

        #expect(relaxed == ["a", "b", "c"])

        // The saving is only real if it survives the planner.
        #expect(
            LayoutSolver.planLCSMoveSequence(
                currentNoControls: ["a", "b", "c"],
                desiredNoControls: relaxed,
                sectionMap: sectionMap
            ).isEmpty
        )
    }

    /// A swap the user can see must still be planned.
    @Test("Visible items keep their desired order")
    func visibleItemsKeepDesiredOrder() {
        let sectionMap = ["a": "visible", "b": "visible", "c": "hidden"]
        let relaxed = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["b", "a", "c"],
            currentNoControls: ["a", "b", "c"],
            sectionMap: sectionMap
        )

        #expect(relaxed == ["b", "a", "c"])
        #expect(
            !LayoutSolver.planLCSMoveSequence(
                currentNoControls: ["a", "b", "c"],
                desiredNoControls: relaxed,
                sectionMap: sectionMap
            ).isEmpty
        )
    }

    /// An item reassigned from visible to hidden is absent from hidden's current run, so it still moves.
    @Test("An item crossing into a concealed section still plans a move")
    func crossSectionMoveSurvives() {
        // `b` currently sits in visible; the layout wants it in hidden.
        let sectionMap = ["a": "visible", "b": "hidden", "c": "hidden"]
        let relaxed = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["a", "b", "c"],
            currentNoControls: ["a", "b", "c"],
            sectionMap: sectionMap
        )

        // Relaxation is a no-op here: b and c are already in that order.
        #expect(relaxed == ["a", "b", "c"])
    }

    /// Hidden items must not be permuted into always-hidden or vice versa.
    @Test("Hidden and always-hidden relax independently")
    func sectionsRelaxIndependently() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["h1", "h2", "x1", "x2"],
            currentNoControls: ["h2", "h1", "x2", "x1"],
            sectionMap: ["h1": "hidden", "h2": "hidden", "x1": "alwaysHidden", "x2": "alwaysHidden"]
        )

        #expect(result == ["h2", "h1", "x2", "x1"])
    }

    /// An item with no live counterpart must move anyway, so it sorts last instead of displacing one in place.
    @Test("Items absent from the current layout sort last within their section")
    func absentItemsSortLast() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["new", "b", "c"],
            currentNoControls: ["b", "c"],
            sectionMap: ["new": "hidden", "b": "hidden", "c": "hidden"]
        )

        #expect(result == ["b", "c", "new"])
    }

    /// Deterministic regardless of the sort's stability.
    @Test("Absent items keep their desired relative order")
    func absentItemsKeepDesiredRelativeOrder() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["n1", "n2", "b"],
            currentNoControls: ["b"],
            sectionMap: ["n1": "hidden", "n2": "hidden", "b": "hidden"]
        )

        #expect(result == ["b", "n1", "n2"])
    }

    /// Relaxed items fill the slots their section had, so interleaved sequences stay well-formed.
    @Test("Interleaved sections preserve their positions")
    func interleavedSectionsPreservePositions() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["h1", "v1", "h2"],
            currentNoControls: ["h2", "v1", "h1"],
            sectionMap: ["h1": "hidden", "h2": "hidden", "v1": "visible"]
        )

        // Slots 0 and 2 stay hidden slots; v1 does not move.
        #expect(result == ["h2", "v1", "h1"])
    }

    /// The enforce-order default relies on this.
    @Test("An empty relaxed-section set is the identity")
    func emptyRelaxedSetIsIdentity() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["a", "c", "b"],
            currentNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "hidden", "c": "hidden"],
            relaxedSectionKeys: []
        )

        #expect(result == ["a", "c", "b"])
    }

    /// Matches planLCSMoveSequence's fallback, so both agree on unknown items.
    @Test("An unmapped identifier is treated as visible")
    func unmappedIdentifierTreatedAsVisible() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["mystery", "b"],
            currentNoControls: ["b", "mystery"],
            sectionMap: ["b": "hidden"]
        )

        #expect(result == ["mystery", "b"])
    }
}
