//
//  RepairCauseTraitsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Each repair cause says what its requests do to the passes around them")
struct RepairCauseTraitsTests {
    typealias Cause = RepairOrchestrator.Cause

    private struct Pinned {
        let user: Bool
        let layout: Bool
        let callsOff: Bool
        let refills: Bool
        let keepsTurn: Bool
    }

    private static let automatic = Pinned(user: false, layout: false, callsOff: false, refills: false, keepsTurn: false)
    private static let userLayoutChange = Pinned(user: true, layout: true, callsOff: false, refills: true, keepsTurn: true)
    private static let userInput = Pinned(user: true, layout: false, callsOff: true, refills: true, keepsTurn: true)

    private static let table: [Cause: Pinned] = [
        .userDragEnded: userLayoutChange,
        .moveFulfilled: automatic,
        .structuralDriftObserved: automatic,
        .revealHideTransition: automatic,
        .settled: automatic,
        .restrictionChanged: automatic,
        .cachePublished: automatic,
        .nativeOverflowChanged: automatic,
        .arrivalDisturbedOrder: automatic,
        .layoutApplyBlocked: automatic,
        .rearmed: automatic,
        .userEdit: userLayoutChange,
        .profileApplied: automatic,
        .settingChanged: automatic,
        .sectionRevealed: Pinned(user: true, layout: false, callsOff: false, refills: true, keepsTurn: true),
        .revealStarting: userInput,
        .userDragStarted: userInput,
        .userClickedItem: userInput,
        .policyReveal: Pinned(user: false, layout: false, callsOff: false, refills: false, keepsTurn: true),
        .displayChanged: Pinned(user: false, layout: false, callsOff: true, refills: true, keepsTurn: false),
        .spaceChanged: automatic,
        .appLaunched: automatic,
        .appTerminated: automatic,
    ]

    private func pinned(_ cause: Cause) throws -> Pinned {
        try #require(Self.table[cause], "\(cause.rawValue) has no row in the table")
    }

    @Test("Every cause has a row")
    func everyCauseHasARow() {
        #expect(Set(Self.table.keys) == Set(Cause.allCases))
    }

    @Test("Each cause reports the traits in its row", arguments: Cause.allCases)
    func traitsMatchTheTable(cause: Cause) throws {
        let row = try pinned(cause)
        let traits = cause.traits
        #expect(traits.isUserAction == row.user)
        #expect(traits.isLayoutChangeByUser == row.layout)
        #expect(traits.callsOffPlannedWork == row.callsOff)
        #expect(traits.refillsBudget == row.refills)
        #expect(traits.keepsTurnOnUserInput == row.keepsTurn)
    }

    @Test("Only a layout change by the user tells the orchestrator's listener", arguments: Cause.allCases)
    func layoutChangeIsAnnounced(cause: Cause) throws {
        let row = try pinned(cause)
        let repairs = RepairOrchestrator()
        var told = false
        repairs.onUserLayoutChange = { told = true }

        repairs.request(.revealReconcile, cause: cause)

        #expect(told == row.layout)
    }

    @Test("A cause that calls off planned work turns away a pass asked for before it", arguments: Cause.allCases)
    func plannedPassIsCalledOff(cause: Cause) async throws {
        let row = try pinned(cause)
        let repairs = RepairOrchestrator()
        repairs.request(.postRestrictionRepair, cause: .restrictionChanged)

        repairs.request(.revealReconcile, cause: cause)

        let hold = await repairs.enter(.postRestrictionRepair)
        #expect((hold == nil) == row.callsOff)
        if let hold {
            repairs.leave(hold)
        }
    }

    @Test("A cause that refills the budget lifts the loop pause", arguments: Cause.allCases)
    func budgetIsRefilled(cause: Cause) async throws {
        let row = try pinned(cause)
        let repairs = RepairOrchestrator()
        for _ in 0 ... AutomaticWriteBudget.limit {
            guard let hold = await repairs.enter(.postRestrictionRepair) else { break }
            StoreWriteAudit.note(StoreWritePermit(hold), write: "test")
            repairs.leave(hold)
        }

        repairs.request(.revealReconcile, cause: cause)

        let hold = await repairs.enter(.structuralNormalization)
        #expect((hold != nil) == row.refills)
        if let hold {
            repairs.leave(hold)
        }
    }

    @Test("A cause that keeps its turn survives a later click", arguments: Cause.allCases)
    func requestSurvivesAClick(cause: Cause) throws {
        let row = try pinned(cause)
        let repairs = RepairOrchestrator()
        repairs.request(.revealReconcile, cause: cause)

        repairs.interruptAutomaticWork(by: .userClickedItem)

        let waiting = repairs.ledger.causesWaiting(for: .revealReconcile)
        #expect(waiting == (row.keepsTurn ? [cause] : []))
    }
}
