//
//  RelaxConcealedSectionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterization tests for LayoutSolver.relaxConcealedSectionOrder.
///
/// The relaxation exists because a move costs the same whether or not its
/// result can be seen: the cursor is hijacked, a drag is synthesised, the
/// landing is polled. Reordering items parked thousands of points
/// off-screen spends that cost on something the Thaw Bar renders from the
/// cache anyway. Rewriting the *desired* sequence — rather than filtering
/// the planned moves — is what makes the saving safe: the LCS then sees
/// those items as already in place, so no surviving move is left anchored
/// against an item the plan assumed had shifted.
///
/// Membership is never surrendered, only intra-section order.
@Suite("Relax concealed section order")
struct RelaxConcealedSectionOrderTests {
    /// Items already in their desired order are unchanged: relaxation
    /// must not invent churn of its own.
    @Test("An already-matching sequence is returned unchanged")
    func matchingSequenceUnchanged() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["a", "b", "c"],
            currentNoControls: ["a", "b", "c"],
            sectionMap: ["a": "visible", "b": "hidden", "c": "hidden"]
        )

        #expect(result == ["a", "b", "c"])
    }

    /// The point of the exercise: two hidden items in the "wrong" order
    /// are rewritten to the order they already sit in, so the LCS finds
    /// them stable and plans nothing.
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

    /// Visible order is not concealed order. A swap the user can see must
    /// still be planned.
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

    /// Membership still moves. An item the layout reassigns from visible
    /// to hidden is absent from hidden's current run, so relaxation cannot
    /// excuse it from moving.
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

    /// The two concealed sections are relaxed independently — hidden
    /// items must not be permuted into always-hidden or vice versa.
    @Test("Hidden and always-hidden relax independently")
    func sectionsRelaxIndependently() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["h1", "h2", "x1", "x2"],
            currentNoControls: ["h2", "h1", "x2", "x1"],
            sectionMap: ["h1": "hidden", "h2": "hidden", "x1": "alwaysHidden", "x2": "alwaysHidden"]
        )

        #expect(result == ["h2", "h1", "x2", "x1"])
    }

    /// An item with no live counterpart has to be moved regardless of what
    /// the relaxation says, so it sorts last within its section rather
    /// than displacing an item that is already in place.
    @Test("Items absent from the current layout sort last within their section")
    func absentItemsSortLast() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["new", "b", "c"],
            currentNoControls: ["b", "c"],
            sectionMap: ["new": "hidden", "b": "hidden", "c": "hidden"]
        )

        #expect(result == ["b", "c", "new"])
    }

    /// Two absent items keep their desired order relative to each other,
    /// so the rewrite is deterministic rather than dependent on the sort's
    /// stability.
    @Test("Absent items keep their desired relative order")
    func absentItemsKeepDesiredRelativeOrder() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["n1", "n2", "b"],
            currentNoControls: ["b"],
            sectionMap: ["n1": "hidden", "n2": "hidden", "b": "hidden"]
        )

        #expect(result == ["b", "n1", "n2"])
    }

    /// Relaxed items are emitted wherever the desired sequence had one, so
    /// a sequence that interleaves sections stays well-formed: positions
    /// are preserved even though contents are permuted.
    @Test("Interleaved sections preserve their positions")
    func interleavedSectionsPreservePositions() {
        let result = LayoutSolver.relaxConcealedSectionOrder(
            desiredNoControls: ["h1", "v1", "h2"],
            currentNoControls: ["h2", "v1", "h1"],
            sectionMap: ["h1": "hidden", "h2": "hidden", "v1": "visible"]
        )

        // Slots 0 and 2 stay hidden slots; only which hidden item lands in
        // each changes. v1 does not move.
        #expect(result == ["h2", "v1", "h1"])
    }

    /// With no relaxed sections the transform is the identity, which is
    /// what the enforce-order default relies on.
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

    /// An unmapped identifier defaults to visible, matching
    /// planLCSMoveSequence's own fallback, so the two agree about which
    /// section an unknown item belongs to.
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
