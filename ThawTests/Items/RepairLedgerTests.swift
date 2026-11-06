//
//  RepairLedgerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Repair work is stamped with what asked for it")
struct RepairLedgerTests {
    private typealias CauseCount = RepairLedger.CauseCount

    @Test("Requests for one pass merge until it wakes, in the order each cause first asked")
    func requestsMergeUntilThePassWakes() {
        var ledger = RepairLedger()
        let start = ContinuousClock.now

        ledger.request(.postRestrictionRepair, cause: .restrictionChanged, at: start)
        ledger.request(.postRestrictionRepair, cause: .settled, at: start + .milliseconds(200))
        ledger.request(.postRestrictionRepair, cause: .restrictionChanged, at: start + .milliseconds(400))
        let run = ledger.begin(.postRestrictionRepair, at: start + .milliseconds(1600))

        #expect(run.requests == 3)
        #expect(run.causes == [
            CauseCount(cause: .restrictionChanged, count: 2),
            CauseCount(cause: .settled, count: 1),
        ])
        #expect(run.waited == .milliseconds(1600))
        #expect(run.overlapping.isEmpty)
        #expect(run.causeSummary == "restrictionChanged×2, settled")
    }

    @Test("A pass that wakes while another is still running reports the overlap")
    func overlapIsReported() {
        var ledger = RepairLedger()
        ledger.request(.postRestrictionRepair, cause: .settled)
        ledger.request(.structuralNormalization, cause: .settled)

        #expect(ledger.begin(.structuralNormalization).overlapping.isEmpty)
        #expect(ledger.begin(.postRestrictionRepair).overlapping == [.structuralNormalization])

        ledger.end(.structuralNormalization)
        ledger.request(.overflowRebalance, cause: .cachePublished)
        #expect(ledger.begin(.overflowRebalance).overlapping == [.postRestrictionRepair])
    }

    @Test("A finished pass no longer counts as running")
    func endClearsTheRun() {
        var ledger = RepairLedger()
        let start = ContinuousClock.now

        _ = ledger.begin(.arrivalOrderRestore, at: start)
        #expect(ledger.isRunning(.arrivalOrderRestore))
        #expect(ledger.end(.arrivalOrderRestore, at: start + .seconds(2)) == .seconds(2))
        #expect(!ledger.isRunning(.arrivalOrderRestore))
        #expect(ledger.end(.arrivalOrderRestore) == .zero)
    }

    @Test("Withdrawn requests are not credited to a later run")
    func withdrawnRequestsAreForgotten() {
        var ledger = RepairLedger()

        ledger.request(.structuralNormalization, cause: .userDragEnded)
        ledger.withdraw(.structuralNormalization)
        ledger.request(.structuralNormalization, cause: .moveFulfilled)
        let run = ledger.begin(.structuralNormalization)

        #expect(run.causes == [CauseCount(cause: .moveFulfilled, count: 1)])
        #expect(run.requests == 1)
    }

    @Test("A pass nothing asked for still runs and says so")
    func unrequestedRun() {
        var ledger = RepairLedger()
        let run = ledger.begin(.deferredLayoutReconcile)

        #expect(run.requests == 0)
        #expect(run.waited == .zero)
        #expect(run.causeSummary == "unrequested")
    }

    @Test("A declined scheduler leaves nothing waiting; an armed one does")
    func schedulersStampTheirRequests() {
        let manager = MenuBarItemManager()
        defer { manager.structuralNormalizationTask?.cancel() }

        manager.isInStartupSettling = true
        manager.scheduleStructuralNormalization(cause: .userDragEnded)
        #expect(manager.repairs.ledger.causesWaiting(for: .structuralNormalization).isEmpty)

        manager.isInStartupSettling = false
        manager.scheduleStructuralNormalization(cause: .userDragEnded)
        manager.scheduleStructuralNormalization(cause: .moveFulfilled)
        #expect(manager.repairs.ledger.causesWaiting(for: .structuralNormalization) == [.userDragEnded, .moveFulfilled])
    }
}
