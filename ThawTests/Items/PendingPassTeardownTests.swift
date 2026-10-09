//
//  PendingPassTeardownTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Calling off armed repair passes cancels them, clears what they owed and forgets their requests")
struct PendingPassTeardownTests {
    @MainActor
    private final class Owner {
        var repairTask: Task<Void, Never>?
        var repairNeedsRerun = false
        var normalizationTask: Task<Void, Never>?
    }

    private typealias Teardown = PendingPassTeardown<Owner>

    private let repair = Teardown.Pass(
        work: .postRestrictionRepair,
        task: \.repairTask,
        owedRerun: \.repairNeedsRerun
    )
    private let normalization = Teardown.Pass(work: .structuralNormalization, task: \.normalizationTask)

    /// A task that stays alive until it is cancelled, standing in for a pass's debounce.
    private func waitingTask() -> Task<Void, Never> {
        Task { try? await Task.sleep(for: .seconds(3600)) }
    }

    @Test("Each pass's task is cancelled and dropped, its owed rerun cleared and its requests forgotten")
    func callsOffEveryPass() {
        let owner = Owner()
        let repairs = RepairOrchestrator()
        let repairTask = waitingTask()
        let normalizationTask = waitingTask()
        owner.repairTask = repairTask
        owner.repairNeedsRerun = true
        owner.normalizationTask = normalizationTask
        repairs.request(.postRestrictionRepair, cause: .restrictionChanged)
        repairs.request(.structuralNormalization, cause: .userDragEnded)
        repairs.request(.overflowRebalance, cause: .cachePublished)

        Teardown.callOff([repair, normalization], of: owner, on: repairs)

        #expect(repairTask.isCancelled)
        #expect(normalizationTask.isCancelled)
        #expect(owner.repairTask == nil)
        #expect(owner.normalizationTask == nil)
        #expect(!owner.repairNeedsRerun)
        #expect(repairs.ledger.causesWaiting(for: .postRestrictionRepair).isEmpty)
        #expect(repairs.ledger.causesWaiting(for: .structuralNormalization).isEmpty)
        #expect(repairs.ledger.causesWaiting(for: .overflowRebalance) == [.cachePublished])
    }

    @Test("A pass that is not named keeps its task and its requests")
    func leavesOtherPassesAlone() {
        let owner = Owner()
        let repairs = RepairOrchestrator()
        let repairTask = waitingTask()
        let normalizationTask = waitingTask()
        defer { repairTask.cancel() }
        owner.repairTask = repairTask
        owner.repairNeedsRerun = true
        owner.normalizationTask = normalizationTask
        repairs.request(.postRestrictionRepair, cause: .restrictionChanged)
        repairs.request(.structuralNormalization, cause: .userDragEnded)

        Teardown.callOff([normalization], of: owner, on: repairs)

        #expect(normalizationTask.isCancelled)
        #expect(owner.normalizationTask == nil)
        #expect(repairs.ledger.causesWaiting(for: .structuralNormalization).isEmpty)
        #expect(!repairTask.isCancelled)
        #expect(owner.repairTask == repairTask)
        #expect(owner.repairNeedsRerun)
        #expect(repairs.ledger.causesWaiting(for: .postRestrictionRepair) == [.restrictionChanged])
    }

    @Test("Every task is cancelled before the caller's own step, and every request forgotten after it")
    func cancelsThenForgets() {
        let owner = Owner()
        let repairs = RepairOrchestrator()
        let repairTask = waitingTask()
        let normalizationTask = waitingTask()
        owner.repairTask = repairTask
        owner.repairNeedsRerun = true
        owner.normalizationTask = normalizationTask
        repairs.request(.postRestrictionRepair, cause: .restrictionChanged)
        repairs.request(.structuralNormalization, cause: .userDragEnded)
        var stepRan = false

        Teardown.callOff([repair, normalization], of: owner, on: repairs) {
            stepRan = true
            #expect(repairTask.isCancelled)
            #expect(normalizationTask.isCancelled)
            #expect(owner.repairTask == nil)
            #expect(owner.normalizationTask == nil)
            #expect(!owner.repairNeedsRerun)
            #expect(repairs.ledger.causesWaiting(for: .postRestrictionRepair) == [.restrictionChanged])
            #expect(repairs.ledger.causesWaiting(for: .structuralNormalization) == [.userDragEnded])
        }

        #expect(stepRan)
        #expect(repairs.ledger.causesWaiting(for: .postRestrictionRepair).isEmpty)
        #expect(repairs.ledger.causesWaiting(for: .structuralNormalization).isEmpty)
    }

    @Test("Calling off a pass that was never armed still forgets its requests")
    func forgetsRequestsOfAnUnarmedPass() {
        let owner = Owner()
        let repairs = RepairOrchestrator()
        repairs.request(.postRestrictionRepair, cause: .settled)

        Teardown.callOff([repair], of: owner, on: repairs)

        #expect(owner.repairTask == nil)
        #expect(repairs.ledger.causesWaiting(for: .postRestrictionRepair).isEmpty)
    }

    @Test("The item manager's passes are called off through its own properties")
    func itemManagerPasses() throws {
        let manager = MenuBarItemManager()
        manager.noteRestrictionChange()
        manager.scheduleStructuralNormalization(cause: .userDragEnded)
        manager.postRestrictionRepairNeedsRerun = true
        let repairTask = try #require(manager.postRestrictionRepairTask)
        let normalizationTask = try #require(manager.structuralNormalizationTask)

        PendingPassTeardown.callOff(
            [.postRestrictionRepair, .structuralNormalization],
            of: manager,
            on: manager.repairs
        )

        #expect(repairTask.isCancelled)
        #expect(normalizationTask.isCancelled)
        #expect(manager.postRestrictionRepairTask == nil)
        #expect(manager.structuralNormalizationTask == nil)
        #expect(!manager.postRestrictionRepairNeedsRerun)
        #expect(manager.repairs.ledger.causesWaiting(for: .postRestrictionRepair).isEmpty)
        #expect(manager.repairs.ledger.causesWaiting(for: .structuralNormalization).isEmpty)
    }
}
