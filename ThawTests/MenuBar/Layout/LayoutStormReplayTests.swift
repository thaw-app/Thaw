//
//  LayoutStormReplayTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Log-replay lock for the #881 layout storm.
///
/// Drives the real `LayoutSolver.planLCSMoveSequence` with the menu bar
/// shape a reporter's machine was actually in when the storm fired, so the
/// regression is pinned to field data rather than to a hand-built example.
/// See ``LayoutStormLog`` for provenance.
///
/// The bug was never in how the planner ordered items — it was that a second
/// planner existed. On notched displays `applyProfileLayout` took a full-sort
/// path that re-inserted items one at a time and trimmed its replay by the
/// longest correctly ordered *prefix*, so a single item arriving out of place
/// near the front of the row invalidated the trim and replayed everything
/// after it. These tests characterize the gap between the two.
@Suite("Layout storm replay (#881)")
struct LayoutStormReplayTests {
    /// The reporter's row differs from the profile by exactly one item: LM
    /// Studio attached left of Sound and Google Drive, the profile wants it
    /// right of both. Everything else is already in order.
    @Test("Only the newly arrived item is out of place")
    func onlyTheNewItemIsOutOfPlace() {
        let current = LayoutStormLog.currentVisible
        let desired = LayoutStormLog.desiredVisible

        #expect(Set(current) == Set(desired), "same items, different order")

        let newItem = "ai.elementlabs.lmstudio:Item-0"
        #expect(current.filter { $0 != newItem } == desired.filter { $0 != newItem })
    }

    /// The lock. One displaced item costs one move.
    @Test("The planner moves one item, not the whole row")
    func plannerMovesOnlyTheDisplacedItem() {
        let moves = LayoutSolver.planLCSMoveSequence(
            currentNoControls: LayoutStormLog.currentVisible + LayoutStormLog.currentHidden,
            desiredNoControls: LayoutStormLog.desiredVisible + LayoutStormLog.currentHidden,
            sectionMap: LayoutStormLog.sectionMap
        )

        #expect(moves.count == 1)
        #expect(moves.first?.uid == "ai.elementlabs.lmstudio:Item-0")
    }

    /// The same input under the deleted path produced ten drags. At the 411ms
    /// per move this log averages, that is the difference between a move the
    /// reporter would not notice and the 4.1s seizure they filmed — and for
    /// users with 200+ items, between under a second and over a minute.
    @Test("The deleted full-sort path dragged ten items for the same input")
    func fullSortDraggedTheEntireRow() {
        let moves = LayoutSolver.planLCSMoveSequence(
            currentNoControls: LayoutStormLog.currentVisible + LayoutStormLog.currentHidden,
            desiredNoControls: LayoutStormLog.desiredVisible + LayoutStormLog.currentHidden,
            sectionMap: LayoutStormLog.sectionMap
        )

        #expect(LayoutStormLog.fullSortDraggedItems.count == 10)
        #expect(moves.count < LayoutStormLog.fullSortDraggedItems.count)
    }

    /// n - |LCS| is the floor on move count for unique identifiers, so the
    /// planner is not merely better than full sort, it is optimal. Pinning
    /// this stops a future "optimization" from trading moves for planning
    /// speed — the wrong trade when planning costs microseconds and a move
    /// costs a synthetic drag.
    @Test("The move count matches the theoretical floor")
    func moveCountIsOptimal() {
        let current = LayoutStormLog.currentVisible
        let desired = LayoutStormLog.desiredVisible
        let retained = LayoutSolver.longestCommonSubsequence(current, desired)

        #expect(desired.count - retained.count == 1)
    }

    /// An unchanged row plans nothing at all. The storm fired on an app
    /// launch, and most cache cycles in the log are no-ops; if this ever
    /// starts planning moves, Thaw churns the bar on every tick.
    @Test("An already-correct row plans no moves")
    func steadyStatePlansNothing() {
        let moves = LayoutSolver.planLCSMoveSequence(
            currentNoControls: LayoutStormLog.desiredVisible,
            desiredNoControls: LayoutStormLog.desiredVisible,
            sectionMap: LayoutStormLog.sectionMap
        )
        #expect(moves.isEmpty)
    }
}
