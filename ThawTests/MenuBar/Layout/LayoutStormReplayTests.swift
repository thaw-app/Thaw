//
//  LayoutStormReplayTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Replays the #881 layout storm through `LayoutSolver.planLCSMoveSequence`
/// using a reporter's real bar (see ``LayoutStormLog``).
///
/// The bug was a second planner: on notched displays `applyProfileLayout` used a
/// full-sort path that trimmed its replay by the longest ordered prefix, so one
/// misplaced item near the front replayed everything after it.
@Suite("Layout storm replay (#881)")
struct LayoutStormReplayTests {
    /// LM Studio attached left of Sound and Google Drive; the profile wants it right of both.
    @Test("Only the newly arrived item is out of place")
    func onlyTheNewItemIsOutOfPlace() {
        let current = LayoutStormLog.currentVisible
        let desired = LayoutStormLog.desiredVisible

        #expect(Set(current) == Set(desired), "same items, different order")

        let newItem = "ai.elementlabs.lmstudio:Item-0"
        #expect(current.filter { $0 != newItem } == desired.filter { $0 != newItem })
    }

    /// One displaced item costs one move.
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

    /// The deleted path made ten drags. At this log's 411ms per move that is the
    /// 4.1s seizure the reporter filmed, and over a minute with 200+ items.
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

    /// n - |LCS| is the floor for unique identifiers, so the planner is optimal. A
    /// move is a synthetic drag and planning costs microseconds; never trade moves for speed.
    @Test("The move count matches the theoretical floor")
    func moveCountIsOptimal() {
        let current = LayoutStormLog.currentVisible
        let desired = LayoutStormLog.desiredVisible
        let retained = LayoutSolver.longestCommonSubsequence(current, desired)

        #expect(desired.count - retained.count == 1)
    }

    /// Most cache cycles are no-ops; planning moves here would churn the bar every tick.
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
