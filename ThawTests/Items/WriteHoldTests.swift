//
//  WriteHoldTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// A pass holds on the first check in its list whose condition holds, and on nothing else.
@MainActor
@Suite("Write hold")
struct WriteHoldTests {
    @Test("The first holding check in the list order wins")
    func firstHoldingCheckWins() {
        var situation = WriteHold.Situation()
        situation.membershipReadPending = true
        situation.userDragging = true
        #expect(WriteHold.first([.userDragging, .membershipReadPending], in: situation) == .userDragging)
        #expect(WriteHold.first([.membershipReadPending, .userDragging], in: situation) == .membershipReadPending)
    }

    @Test("No listed check holding returns nil")
    func noListedCheckHolds() {
        #expect(WriteHold.first(Array(WriteHold.Check.allCases), in: WriteHold.Situation()) == nil)
        var situation = WriteHold.Situation()
        situation.profileApplying = true
        #expect(WriteHold.first([.startupSettling, .circuitBreakerOpen], in: situation) == nil)
    }

    @Test("A holding check outside the list is ignored")
    func unlistedCheckIsIgnored() {
        var situation = WriteHold.Situation()
        situation.sectionRevealed = true
        #expect(WriteHold.first([.layoutPublicationStale, .profileApplying], in: situation) == nil)
        #expect(WriteHold.first([.layoutPublicationStale, .sectionRevealed], in: situation) == .sectionRevealed)
    }

    @Test("Every check is wired to its own condition")
    func everyCheckIsWiredToAField() {
        var all = WriteHold.Situation()
        all.startupSettling = true
        all.circuitBreakerOpen = true
        all.notificationCenterSuspended = true
        all.userDragging = true
        all.profileApplying = true
        all.membershipReadPending = true
        all.layoutPublicationStale = true
        all.sectionRevealed = true
        all.revealTransitionActive = true
        all.barOnUncachedDisplay = true
        all.barReadIncomplete = true
        #expect(all.heldChecks == Set(WriteHold.Check.allCases))
    }
}

/// The normalization pass rechecks reveal state after taking the repair lane, so a reveal that
/// starts during its waits rearms it instead of being written over.
@Suite("Structural normalization holds")
struct StructuralNormalizationHoldsTests {
    @Test("The checks include both reveal checks")
    func checksCoverRevealState() {
        #expect(StructuralNormalizationHolds.checks.contains(.sectionRevealed))
        #expect(StructuralNormalizationHolds.checks.contains(.revealTransitionActive))
    }

    /// 2026-11-05: the bar moved to another display and the pass, reading
    /// frames from both bars, moved an item that was in place.
    @Test("The pass waits while the cache is on another display than the bar")
    func checksCoverDisplayMove() {
        var situation = WriteHold.Situation()
        situation.barOnUncachedDisplay = true
        #expect(WriteHold.first(StructuralNormalizationHolds.checks, in: situation) == .barOnUncachedDisplay)
    }

    /// A structural pass on a read that missed items would re-lay the whole bar, so it waits.
    @Test("The pass waits while the last bar read was incomplete, and says so")
    func checksCoverIncompleteRead() {
        var situation = WriteHold.Situation()
        situation.barReadIncomplete = true

        let held = WriteHold.first(StructuralNormalizationHolds.checks, in: situation)

        #expect(held == .barReadIncomplete)
        #expect(held.flatMap(StructuralNormalizationHolds.deferralNote(for:))
            == "structural normalization: the last bar read was incomplete; deferring")
        #expect(StructuralNormalizationHolds.deferralNote(for: .sectionRevealed) == nil)
        StructuralNormalizationHolds.logDeferral(on: .barReadIncomplete)
        StructuralNormalizationHolds.logDeferral(on: .sectionRevealed)
    }

    @Test("The item manager reports the bar read as incomplete before any read")
    @MainActor func managerSituationReadsTheLastBarRead() {
        let manager = MenuBarItemManager()
        #expect(manager.structuralNormalizationSituation().barReadIncomplete)
    }
}

/// The record of the cache's last bar read, which the settle and the structural pass both trust.
@Suite("Bar read record")
struct BarReadRecordTests {
    @Test("Each read gets a new number and is complete only when the walk finished with fresh answers")
    func readsAreNumberedAndJudged() {
        var record = BarReadRecord()
        #expect(record.generation == 0)
        #expect(!record.isComplete)

        record.note(.init(walkCompleted: true, hasFreshKnownInventory: true))
        #expect(record.generation == 1)
        #expect(record.isComplete)

        record.note(.init(walkCompleted: false, hasFreshKnownInventory: true))
        #expect(record.generation == 2)
        #expect(!record.isComplete)

        record.note(.init(walkCompleted: true, hasFreshKnownInventory: false))
        #expect(!record.isComplete)

        record.note(nil)
        #expect(record.generation == 3, "a pass that never read the bar")
    }

    @Test("A read merged with older items is incomplete")
    func mergedReadIsIncomplete() {
        var record = BarReadRecord()

        record.note(.init(walkCompleted: true, hasFreshKnownInventory: true, mergedWithOlderItems: true))

        #expect(record.generation == 1)
        #expect(!record.isComplete)
    }
}
