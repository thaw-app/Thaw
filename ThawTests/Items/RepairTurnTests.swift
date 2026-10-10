//
//  RepairTurnTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("A repair pass reads the bar before it takes the lane")
struct RepairTurnTests {
    @Test("The lane is free while the bar is being read")
    func laneIsFreeDuringTheRead() async {
        let repairs = RepairOrchestrator()
        var doorDuringRead: StoreWritePermit.Door?

        _ = await RepairTurn.run(.revealReconcile, on: repairs, read: { () -> Int? in
            doorDuringRead = repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { $0.door }
            return 1
        }, write: { _, _ in })

        #expect(doorDuringRead == .repairLane(.manualLayoutEdit))
    }

    @Test("The restore holds the lane and gets the reading")
    func restoreHoldsTheLane() async {
        let repairs = RepairOrchestrator()
        var received: Int?
        var doorDuringRestore: StoreWritePermit.Door?
        var restoreDoor: StoreWritePermit.Door?

        _ = await RepairTurn.run(.revealReconcile, on: repairs, read: { 7 }, write: { reading, permit in
            received = reading
            restoreDoor = permit.door
            doorDuringRestore = repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { $0.door }
        })

        #expect(received == 7)
        #expect(restoreDoor == .repairLane(.revealReconcile))
        #expect(doorDuringRestore == .unsequenced("manualLayoutEdit while revealReconcile was writing"))
        #expect(!repairs.ledger.isRunning(.revealReconcile))
    }

    @Test("A reading that waited in the queue is dropped")
    func staleReadingIsDropped() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.postRestrictionRepair))
        var received: Int? = -1

        let turn = Task {
            _ = await RepairTurn.run(.revealReconcile, on: repairs, readStaleAfter: .milliseconds(20), read: { 7 }, write: { reading, _ in
                received = reading
            })
        }
        try await Task.sleep(for: .milliseconds(120))
        repairs.leave(holder)
        await turn.value

        #expect(received == nil)
    }

    @Test("A reading is dropped when another writer finished after it began, with no wait at all")
    func readingBehindAnotherWriterIsDropped() async {
        let repairs = RepairOrchestrator()
        var received: Int? = -1

        _ = await RepairTurn.run(.revealReconcile, on: repairs, read: { () -> Int? in
            repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { _ in }
            return 7
        }, write: { reading, _ in
            received = reading
        })

        #expect(received == nil)
    }

    @Test("A move that ended during the read drops the reading too")
    func readingBehindAMoveIsDropped() async {
        let repairs = RepairOrchestrator()
        var received: Int? = -1

        _ = await RepairTurn.run(.postRestrictionRepair, on: repairs, read: { () -> Int? in
            repairs.endMove(repairs.beginMove())
            return 7
        }, write: { reading, _, _ in
            received = reading
        })

        #expect(received == nil)
    }

    @Test("Every door counts as a finished writer: the lane, a synchronous write, and a move with or without the lane")
    func everyDoorAdvancesTheGeneration() async throws {
        let repairs = RepairOrchestrator()
        #expect(repairs.writeGeneration == 0)

        let hold = try #require(await repairs.enter(.structuralNormalization))
        #expect(repairs.writeGeneration == 0)
        repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { _ in }
        #expect(repairs.writeGeneration == 1)
        repairs.endMove(repairs.beginMove())
        #expect(repairs.writeGeneration == 2)
        repairs.leave(hold)
        #expect(repairs.writeGeneration == 3)

        repairs.endMove(repairs.beginMove())
        #expect(repairs.writeGeneration == 4)
    }

    @Test("The caller gets back what the write returned")
    func returnsTheWritesOutcome() async {
        let repairs = RepairOrchestrator()

        let outcome = await RepairTurn.run(.postRestrictionRepair, on: repairs, read: { 2 }, write: { reading, _ in
            (reading ?? 0) * 21
        })

        #expect(outcome == 42)
    }

    @Test("A pass that hands its permit back frees the lane while it checks its work")
    func handingThePermitBackFreesTheLane() async {
        let repairs = RepairOrchestrator()
        var doorWhileWriting: StoreWritePermit.Door?
        var doorWhileChecking: StoreWritePermit.Door?

        _ = await RepairTurn.run(.postRestrictionRepair, on: repairs, read: { 1 }, write: { _, permit, writing in
            doorWhileWriting = repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { $0.door }
            writing.end(permit)
            doorWhileChecking = repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { $0.door }
        })

        #expect(doorWhileWriting == .unsequenced("manualLayoutEdit while postRestrictionRepair was writing"))
        #expect(doorWhileChecking == .repairLane(.manualLayoutEdit))
        #expect(!repairs.ledger.isRunning(.postRestrictionRepair))
    }

    @Test("A pass that kept its permit leaves the lane when it returns")
    func keptPermitLeavesOnReturn() async {
        let repairs = RepairOrchestrator()

        _ = await RepairTurn.run(.postRestrictionRepair, on: repairs, read: { 1 }, write: { _, _, writing in
            #expect(!writing.isOver)
        })

        #expect(repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { $0.door } == .repairLane(.manualLayoutEdit))
    }

    @Test("The lane handed back early is not taken from the pass that got it next")
    func earlyHandBackDoesNotEvictTheNextPass() async throws {
        let repairs = RepairOrchestrator()
        var next: RepairLane.Hold?

        _ = await RepairTurn.run(.postRestrictionRepair, on: repairs, read: { 1 }, write: { _, permit, writing in
            writing.end(permit)
            next = await repairs.enter(.structuralNormalization)
        })

        #expect(repairs.writeNow(.manualLayoutEdit, cause: .userEdit) { $0.door }
            == .unsequenced("manualLayoutEdit while structuralNormalization was writing"))
        try repairs.leave(#require(next))
    }

    @Test("A cache read a pass owes is made once, after its turn, and only when owed")
    func aftermathReadsOnce() async {
        let aftermath = RepairTurn.Aftermath()
        var reads = 0

        await aftermath.readCacheIfOwed { reads += 1 }
        #expect(reads == 0)

        aftermath.needsCachePass = true
        await aftermath.readCacheIfOwed { reads += 1 }
        await aftermath.readCacheIfOwed { reads += 1 }
        #expect(reads == 1)
    }

    @Test("A pass's closing read is owed to an aftermath when there is one, and made on the spot otherwise")
    func closingReadIsOwedOrMade() async {
        let aftermath = RepairTurn.Aftermath()
        var reads = 0

        await RepairTurn.Aftermath.closingRead(owedTo: aftermath) { reads += 1 }
        #expect(reads == 0)
        #expect(aftermath.needsCachePass)

        await RepairTurn.Aftermath.closingRead(owedTo: nil) { reads += 1 }
        #expect(reads == 1)
    }

    @Test("A pass sees user work queue behind it, until it has left the lane")
    func passSeesWaitingUserWork() async throws {
        let repairs = RepairOrchestrator()
        var before: Bool?
        var whileQueued: Bool?
        var afterLeaving: Bool?

        _ = await RepairTurn.run(.postRestrictionRepair, on: repairs, read: { 1 }, write: { _, permit, writing in
            before = writing.userWorkIsWaiting
            let edit = Task { @MainActor in
                if let hold = await repairs.enterForUserEdit() {
                    repairs.leave(hold)
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
            whileQueued = writing.userWorkIsWaiting
            writing.end(permit)
            afterLeaving = writing.userWorkIsWaiting
            await edit.value
        })

        #expect(before == false)
        #expect(whileQueued == true)
        #expect(afterLeaving == false)
    }
}
