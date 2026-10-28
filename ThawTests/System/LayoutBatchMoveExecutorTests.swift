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
    var barFollows: ((LayoutBatchMovePlan) async -> Bool)?
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
            },
            barFollows: barFollows
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
        let outcome = try await path.executor.run(command("thaw://move-item?item-id=x&item-id=h2&item-id=a&section=hidden&after-id=h1"))

        #expect(path.events == ["input:userEdit", "commit"])
        let plan = try #require(path.plans.first)
        #expect(plan.itemIDs == ["x", "h2", "a"])
        #expect(plan.targetOrder == ["h1", "x", "h2", "a"])
        #expect(outcome == .moved(plan))
    }

    @Test("A Visible move the bar never follows is reported as not applied")
    func unfollowedVisibleMoveIsNotApplied() async throws {
        let path = MovePath()
        path.barFollows = { _ in false }
        let outcome = try await path.executor.run(command("thaw://move-item?item-id=h1&section=visible"))

        guard case let .notApplied(plan) = outcome else {
            Issue.record("expected notApplied, got \(outcome)")
            return
        }
        #expect(plan.itemIDs == ["h1"])
    }

    @Test("A Visible move the bar follows, or one that is not verified, is moved")
    func followedOrUnverifiedMoveIsMoved() async throws {
        let path = MovePath()
        path.barFollows = { _ in true }
        let followed = try await path.executor.run(command("thaw://move-item?item-id=h1&section=visible"))
        path.barFollows = nil
        let unverified = try await path.executor.run(command("thaw://move-item?item-id=h1&section=visible"))

        for outcome in [followed, unverified] {
            guard case .moved = outcome else {
                Issue.record("expected moved, got \(outcome)")
                return
            }
        }
    }

    @Test("Only a Visible target is verified")
    func concealedTargetSkipsVerification() async throws {
        let path = MovePath()
        var checks = 0
        path.barFollows = { _ in
            checks += 1
            return false
        }
        let outcome = try await path.executor.run(command("thaw://move-item?item-id=x&section=hidden&after-id=h1"))

        guard case .moved = outcome else {
            Issue.record("expected moved, got \(outcome)")
            return
        }
        #expect(checks == 0)
    }

    @Test("The poll returns true on the first match without spending the budget")
    func pollStopsOnMatch() async {
        var sleeps = [Duration]()
        var polls = 0
        let followed = await LayoutBatchMoveExecutor.pollBarFollows(
            budget: .seconds(8),
            sleep: { sleeps.append($0) },
            matches: {
                polls += 1
                return polls == 2
            }
        )

        #expect(followed)
        #expect(polls == 2)
        #expect(sleeps == [.milliseconds(400), .seconds(1)])
    }

    @Test("The poll gives up once the budget is spent")
    func pollGivesUpAtDeadline() async {
        var slept = Duration.zero
        var polls = 0
        let followed = await LayoutBatchMoveExecutor.pollBarFollows(
            budget: .seconds(3),
            sleep: { slept += $0 },
            matches: {
                polls += 1
                return false
            }
        )

        #expect(!followed)
        #expect(polls == 4)
        #expect(slept == .milliseconds(3400))
    }

    @Test("The budget outlasts the manager's own apply passes")
    func budgetCoversApplyAttempts() {
        #expect(LayoutBatchMoveExecutor.barApplyBudget > .seconds(MenuBarItemManager.authoredVisibleOrderApplyAttempts))
    }

    @Test("A refused batch never reaches the repair lane or the drop path")
    func refusedBatchDoesNothing() async throws {
        let path = MovePath()
        let outcome = try await path.executor.run(command("thaw://move-item?item-id=h1&item-id=ghost&section=visible"))

        #expect(outcome == .refused(.unknownItem("ghost")))
        #expect(path.events.isEmpty)
    }

    @Test("A move that changes nothing is reported without writing")
    func unchangedMoveDoesNotCommit() async throws {
        let path = MovePath()
        let outcome = try await path.executor.run(command("thaw://move-item?item-id=c&section=visible"))

        guard case .unchanged = outcome else {
            Issue.record("Expected unchanged, got \(outcome)")
            return
        }
        #expect(path.events.isEmpty)
    }

    @Test("A retry the saved order already holds is not applied while the bar still disagrees")
    func unchangedMoveChecksTheBar() async throws {
        let path = MovePath()
        path.barFollows = { _ in false }
        let disagrees = try await path.executor.run(command("thaw://move-item?item-id=c&section=visible"))
        path.barFollows = { _ in true }
        let agrees = try await path.executor.run(command("thaw://move-item?item-id=c&section=visible"))

        guard case .notApplied = disagrees, case .unchanged = agrees else {
            Issue.record("Expected notApplied then unchanged, got \(disagrees) and \(agrees)")
            return
        }
        #expect(path.events.isEmpty)
    }

    @Test("A move the drop path declines is reported as refused")
    func declinedMoveIsRefused() async throws {
        let path = MovePath()
        path.accepts = false
        let outcome = try await path.executor.run(command("thaw://move-item?item-id=h1&section=visible"))

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
        #expect(entry?.groupID == nil)
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
        for request in ["move-item?item-id=a&section=hidden", "list-items?callback=x://y"] {
            #expect(try ReducedModeURLCommand(#require(URL(string: "thaw://\(request)"))) == nil)
        }
    }
}
