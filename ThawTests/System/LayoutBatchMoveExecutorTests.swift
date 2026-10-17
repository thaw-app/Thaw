//
//  LayoutBatchMoveExecutorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Records what the executor hands to the repair lane and the drop path, instead of touching the bar.
@MainActor
private final class MovePath {
    var snapshot = LayoutBatchMoveTests.snapshot
    var accepts = true
    private(set) var events = [String]()
    private(set) var plans = [LayoutBatchMovePlan]()

    var executor: LayoutBatchMoveExecutor {
        LayoutBatchMoveExecutor(
            snapshot: { self.snapshot },
            noteUserInput: { self.events.append("input:\($0.rawValue)") },
            commit: { plan in
                self.events.append("commit")
                self.plans.append(plan)
                return self.accepts
            }
        )
    }
}

@MainActor
@Suite("Move item URL executor")
struct LayoutBatchMoveExecutorTests {
    private func command(_ string: String) throws -> LayoutBatchMove {
        try LayoutBatchMove.parse(#require(URL(string: string))).get()
    }

    @Test("A batch is one user edit followed by a single call to the drop path")
    func batchIsOneUserEditAndOneCommit() async throws {
        let path = MovePath()
        let outcome = try await path.executor.run(command("thaw://move-item?item=x&item=h2&item=a&section=hidden&after=h1"))

        #expect(path.events == ["input:userEdit", "commit"])
        let plan = try #require(path.plans.first)
        #expect(plan.itemIDs == ["x", "h2", "a"])
        #expect(plan.targetOrder == ["h1", "x", "h2", "a"])
        #expect(outcome == .moved(plan))
    }

    @Test("A refused batch never reaches the repair lane or the drop path")
    func refusedBatchDoesNothing() async throws {
        let path = MovePath()
        let outcome = try await path.executor.run(command("thaw://move-item?item=h1&item=ghost&section=visible"))

        #expect(outcome == .refused(.unknownItem("ghost")))
        #expect(path.events.isEmpty)
    }

    @Test("A move that changes nothing is reported without writing")
    func unchangedMoveDoesNotCommit() async throws {
        let path = MovePath()
        let outcome = try await path.executor.run(command("thaw://move-item?item=c&section=visible"))

        guard case .unchanged = outcome else {
            Issue.record("Expected unchanged, got \(outcome)")
            return
        }
        #expect(path.events.isEmpty)
    }

    @Test("A move the drop path declines is reported as refused")
    func declinedMoveIsRefused() async throws {
        let path = MovePath()
        path.accepts = false
        let outcome = try await path.executor.run(command("thaw://move-item?item=h1&section=visible"))

        #expect(outcome == .refused(.moveRefused))
        #expect(path.events == ["input:userEdit", "commit"])
    }

    @Test("The live snapshot lists the Layout pane's items without the dividers")
    func liveSnapshotFollowsTheLayoutPane() {
        let world = LayoutEditorWorld()
        let first = LayoutEditorWorld.item("First")
        let second = LayoutEditorWorld.item("Second")
        world.seat([first, LayoutEditorWorld.item(.hiddenControlItem), second])

        let snapshot = LayoutBatchMoveExecutor.snapshot(appState: world.appState)

        #expect(snapshot.sections[.visible]?.map(\.id) == [first.uniqueIdentifier, second.uniqueIdentifier])
        let entry = snapshot.entry(first.uniqueIdentifier)
        #expect(entry?.isControlItem == false)
        #expect(entry?.isGrouped == false)
    }

    @Test("A live plan becomes a Layout pane drop, marked as a batch when it moves several items")
    func livePlanBecomesADrop() throws {
        let world = LayoutEditorWorld()
        let items = ["A", "B", "C"].map(LayoutEditorWorld.item)
        world.seat(items)
        let ids = items.map(\.uniqueIdentifier)
        let plan = LayoutBatchMovePlan(
            itemIDs: [ids[2], ids[0]],
            source: .visible,
            target: .visible,
            previousTargetOrder: ids,
            targetOrder: [ids[1], ids[2], ids[0]]
        )

        let drop = try #require(LayoutBatchMoveExecutor.drop(for: plan, appState: world.appState))

        #expect(drop.items == [items[2], items[0]])
        #expect(drop.targetOrder == [items[1], items[2], items[0]])
        #expect(drop.previousTargetOrder == items)
        #expect(drop.isBatch)
    }

    @Test("A live plan whose item has gone is declined before anything is written")
    func livePlanWithAGoneItemIsDeclined() async {
        let world = LayoutEditorWorld()
        world.seat([LayoutEditorWorld.item("A")])
        let plan = LayoutBatchMovePlan(
            itemIDs: ["gone"],
            source: .visible,
            target: .visible,
            previousTargetOrder: [],
            targetOrder: ["gone"]
        )

        #expect(LayoutBatchMoveExecutor.drop(for: plan, appState: world.appState)?.items == nil)
        let executor = LayoutBatchMoveExecutor(appState: world.appState)
        #expect(await executor.commit(plan) == false)
    }

    @Test("Reduced mode does not answer move-item or list-items")
    func reducedModeRefusesTheLayoutActions() throws {
        for request in ["move-item?item=a&section=hidden", "list-items?callback=x://y"] {
            #expect(try ReducedModeURLCommand(#require(URL(string: "thaw://\(request)"))) == nil)
        }
    }
}
