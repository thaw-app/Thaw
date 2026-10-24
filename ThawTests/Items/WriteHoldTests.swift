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
        situation.manualArrangement = true
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
        all.manualArrangement = true
        all.membershipReadPending = true
        all.layoutPublicationStale = true
        all.sectionRevealed = true
        all.revealTransitionActive = true
        #expect(all.heldChecks == Set(WriteHold.Check.allCases))
    }
}

/// The normalization pass rechecks reveal state after taking the repair lane, so a reveal that
/// starts during its waits rearms it instead of being written over.
@Suite("Structural normalization holds")
struct StructuralNormalizationHoldsTests {
    @Test("The checks after lane admission include both reveal checks")
    func afterAdmissionCoversRevealState() {
        #expect(StructuralNormalizationHolds.afterAdmission.contains(.sectionRevealed))
        #expect(StructuralNormalizationHolds.afterAdmission.contains(.revealTransitionActive))
    }
}
