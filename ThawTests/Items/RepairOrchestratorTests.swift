//
//  RepairOrchestratorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("The orchestrator gives each writer its turn and its permit")
struct RepairOrchestratorTests {
    @Test("A synchronous write takes the lane when it is free and gives it straight back")
    func writeNowOnAFreeLane() async throws {
        let repairs = RepairOrchestrator()

        let door = repairs.writeNow(.preRevealOrder, cause: .sectionRevealed) { permit in
            permit.door
        }

        #expect(door == .repairLane(.preRevealOrder))
        #expect(!repairs.ledger.isRunning(.preRevealOrder))
        let next = try #require(await repairs.enter(.structuralNormalization))
        repairs.leave(next)
    }

    @Test("A synchronous write still runs while other work holds the lane, and says whose writes it fell between")
    func writeNowOnAHeldLane() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.postRestrictionRepair))

        let door = repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { permit in
            permit.door
        }

        #expect(door == .unsequenced("manualLayoutEdit while postRestrictionRepair was writing"))
        #expect(repairs.ledger.causesWaiting(for: .manualLayoutEdit).isEmpty)
        #expect(repairs.ledger.isRunning(.postRestrictionRepair))
        repairs.leave(holder)
    }

    @Test("Entering marks the work as running and stamps what asked for it; leaving ends it")
    func enterAndLeaveKeepTheAccount() async throws {
        let repairs = RepairOrchestrator()
        repairs.request(.overflowRebalance, cause: .cachePublished)
        #expect(repairs.ledger.causesWaiting(for: .overflowRebalance) == [.cachePublished])

        let hold = try #require(await repairs.enter(.overflowRebalance))
        #expect(repairs.ledger.isRunning(.overflowRebalance))
        #expect(repairs.ledger.causesWaiting(for: .overflowRebalance).isEmpty)

        repairs.leave(hold)
        #expect(!repairs.ledger.isRunning(.overflowRebalance))
    }

    @Test("Work outside the lane is still counted as running, beside the pass that holds the lane")
    func unlanedWorkIsAccountedFor() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.postRestrictionRepair))

        repairs.begin(.deferredLayoutReconcile)
        #expect(repairs.ledger.isRunning(.deferredLayoutReconcile))
        #expect(repairs.ledger.isRunning(.postRestrictionRepair))

        repairs.end(.deferredLayoutReconcile)
        #expect(!repairs.ledger.isRunning(.deferredLayoutReconcile))
        #expect(repairs.ledger.isRunning(.postRestrictionRepair))
        repairs.leave(holder)
    }

    @Test("A pass cancelled while it waits for the lane is told not to write")
    func cancelledWhileQueued() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.postRestrictionRepair))

        let waiting = Task { @MainActor in await repairs.enter(.overflowRebalance) }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        waiting.cancel()

        #expect(await waiting.value == nil)
        #expect(!repairs.ledger.isRunning(.overflowRebalance))
        repairs.leave(holder)
    }

    @Test("The ledger's summary lists what ran, what is running and what is waiting")
    func ledgerSummary() async throws {
        let repairs = RepairOrchestrator()
        repairs.request(.storeHygiene, cause: .cachePublished)
        let hold = try #require(await repairs.enter(.overflowRebalance))

        let summary = repairs.ledger.stateDescription
        #expect(summary.contains("overflowRebalance=1"))
        #expect(summary.contains("awake[overflowRebalance]"))
        #expect(summary.contains("waiting[storeHygiene]"))
        repairs.leave(hold)
    }

    @Test("A move that starts alone keeps a pass waiting until it ends")
    func moveHoldsAFreeLane() async throws {
        let repairs = RepairOrchestrator()
        let move = try #require(repairs.beginMove())
        var passRan = false

        let pass = Task { @MainActor in
            guard let hold = await repairs.enter(.structuralNormalization) else { return }
            passRan = true
            repairs.leave(hold)
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!passRan)
        #expect(repairs.ledger.isRunning(.itemMove))

        repairs.endMove(move)
        await pass.value

        #expect(passRan)
        #expect(!repairs.ledger.isRunning(.itemMove))
    }

    @Test("A move asked for while a pass holds the lane runs without taking it")
    func moveInsideAPassLeavesTheLaneAlone() async throws {
        let repairs = RepairOrchestrator()
        let pass = try #require(await repairs.enter(.postRestrictionRepair))

        let move = repairs.beginMove()
        #expect(move == nil)
        #expect(repairs.ledger.isRunning(.itemMove))
        repairs.endMove(move)

        #expect(!repairs.ledger.isRunning(.itemMove))
        #expect(repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { $0.door }
            == .unsequenced("manualLayoutEdit while postRestrictionRepair was writing"))
        repairs.leave(pass)
    }
}
