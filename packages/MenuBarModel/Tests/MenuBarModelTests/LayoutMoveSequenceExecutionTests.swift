//
//  LayoutMoveSequenceExecutionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing

@Suite("Verified layout move execution")
struct LayoutMoveSequenceExecutionTests {
    @Test("A skipped move cannot anchor a later move")
    func skippedMoveInvalidatesDependentMove() throws {
        let moves = LayoutMoveSequencePlanner.planLCSMoveSequence(
            currentNoControls: ["a", "b", "c"],
            desiredNoControls: ["c", "b", "a"],
            sectionMap: [:]
        )
        var execution = LayoutMoveSequenceExecution(moves: moves)
        let next = execution.next()
        let first = try #require(next)
        #expect(first.uid == "b")
        #expect(first.destination == .rightOfUID("c"))

        // A circuit breaker (or resolver guard) skips b. It is still on the
        // bar, but has not been established to the right of c.
        let dependent = execution.next()
        #expect(dependent == nil, "a must not be dragged relative to the unverified b")
        #expect(execution.needsReplan)
        #expect(!execution.isComplete)
    }

    @Test("Verified movers unlock dependent moves and reach the desired order")
    func verifiedMovesReachDesiredOrder() throws {
        var current = ["a", "b", "c"]
        let desired = ["c", "b", "a"]
        var execution = LayoutMoveSequenceExecution(moves: plan(current: current, desired: desired))
        var movedUIDs = [String]()

        while let move = execution.next() {
            try apply(move, to: &current)
            execution.confirmLastMove()
            movedUIDs.append(move.uid)
        }

        #expect(current == desired)
        #expect(movedUIDs == ["b", "a"])
        #expect(execution.isComplete)
        #expect(!execution.needsReplan)
    }

    @Test("Skipping a mover invalidates transitive dependencies but preserves independent moves")
    func transitiveDependenciesAreDiscarded() throws {
        // Reversal emits c → d, b → c, a → b. The second segment has
        // an independent move x → y, which should still be executed.
        let moves = plan(current: ["a", "b", "c", "d"], desired: ["d", "c", "b", "a"]) +
            plan(current: ["x", "y"], desired: ["y", "x"])
        var execution = LayoutMoveSequenceExecution(moves: moves)
        let first = execution.next()
        #expect(first?.uid == "c")
        // No confirmation: c was skipped.
        let next = execution.next()
        let independent = try #require(next)
        #expect(independent.uid == "x")
        #expect(independent.destination == .rightOfUID("y"))
        execution.confirmLastMove()
        let exhausted = execution.next()
        #expect(exhausted == nil)
        #expect(execution.needsReplan)
        #expect(!execution.isComplete)
    }

    @Test("Both anchor directions require verification")
    func leftAnchorAlsoRequiresVerification() {
        var execution = LayoutMoveSequenceExecution(moves: [
            .init(uid: "b", destination: .rightOfUID("c")),
            .init(uid: "a", destination: .leftOfUID("b")),
        ])
        _ = execution.next()
        let dependent = execution.next()
        #expect(dependent == nil)
        #expect(execution.needsReplan)
    }

    @Test("A failed drag discards even independent moves until geometry is refreshed")
    func failedDragInvalidatesWholePlan() {
        var execution = LayoutMoveSequenceExecution(moves: [
            .init(uid: "b", destination: .rightOfUID("c")),
            .init(uid: "x", destination: .leftOfUID("y")),
        ])
        _ = execution.next()
        execution.invalidate()
        let next = execution.next()
        #expect(next == nil)
        #expect(execution.needsReplan)
        #expect(!execution.isComplete)
    }

    @Test("An unconfirmed final move is not a completed plan")
    func skippedLastMoveIsNotSuccess() {
        var execution = LayoutMoveSequenceExecution(moves: [
            .init(uid: "a", destination: .sectionBoundary(.visible)),
        ])
        _ = execution.next()
        #expect(!execution.isComplete)
        let exhausted = execution.next()
        #expect(exhausted == nil)
        #expect(execution.needsReplan)
        #expect(!execution.isComplete)
    }

    @Test("Replanning after a skipped move uses the observed order")
    func freshPlanDoesNotReuseInvalidatedAnchor() throws {
        let desired = ["c", "b", "a"]
        var execution = LayoutMoveSequenceExecution(moves: plan(current: ["a", "b", "c"], desired: desired))
        _ = execution.next()
        _ = execution.next()
        #expect(execution.needsReplan)

        // b disappears before the refreshed snapshot. A fresh plan places
        // a against c, not against the obsolete b anchor.
        var current = ["a", "c"]
        execution = LayoutMoveSequenceExecution(moves: plan(current: current, desired: desired))
        while let move = execution.next() {
            #expect(move.destination == .rightOfUID("c"))
            try apply(move, to: &current)
            execution.confirmLastMove()
        }
        #expect(current == ["c", "a"])
        #expect(execution.isComplete)
    }

    @Test("An empty plan is complete without a replan")
    func emptyPlanIsComplete() {
        var execution = LayoutMoveSequenceExecution(moves: [])
        let next = execution.next()
        #expect(next == nil)
        #expect(execution.isComplete)
        #expect(!execution.needsReplan)
    }

    private func plan(current: [String], desired: [String]) -> [LayoutMoveSequenceExecution.Move] {
        LayoutMoveSequencePlanner.planLCSMoveSequence(
            currentNoControls: current,
            desiredNoControls: desired,
            sectionMap: [:]
        )
    }

    private func apply(_ move: LayoutMoveSequenceExecution.Move, to items: inout [String]) throws {
        let index = try #require(items.firstIndex(of: move.uid))
        items.remove(at: index)
        switch move.destination {
        case let .leftOfUID(uid):
            let anchor = try #require(items.firstIndex(of: uid))
            items.insert(move.uid, at: anchor)
        case let .rightOfUID(uid):
            let anchor = try #require(items.firstIndex(of: uid))
            items.insert(move.uid, at: anchor + 1)
        case .sectionBoundary:
            Issue.record("These single-segment fixtures must resolve to item anchors")
        }
    }
}
