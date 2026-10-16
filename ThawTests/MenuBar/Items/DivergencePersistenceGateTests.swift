//
//  DivergencePersistenceGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the divergence-persistence gate that decides whether a
/// divergence observation should trigger a saved-layout re-apply.
///
/// A single divergent reading can be transient: a wide application menu
/// shifts status items while it is up (#723). The same divergence must be
/// seen on two consecutive cache cycles before a re-apply.
@Suite("Divergence persistence gate")
struct DivergencePersistenceGateTests {
    private let clock = ContinuousClock()

    /// The first observation defers and arms the pending state.
    @Test("A first divergent observation defers and arms the pending state")
    func firstObservationDefersAndArms() {
        let now = clock.now
        let result = MenuBarItemManager.confirmedDivergence(
            divergedNow: true,
            pendingSince: nil,
            now: now
        )
        #expect(!result.confirmed)
        #expect(result.newPendingSince == now)
    }

    /// A second divergent observation within the staleness window confirms
    /// and resets the pending state.
    @Test("A second divergent observation inside the window confirms and resets")
    func secondObservationWithinWindowConfirmsAndResets() {
        let armedAt = clock.now
        let now = armedAt.advanced(by: .seconds(5))
        let result = MenuBarItemManager.confirmedDivergence(
            divergedNow: true,
            pendingSince: armedAt,
            now: now,
            staleness: .seconds(30)
        )
        #expect(result.confirmed)
        #expect(result.newPendingSince == nil)
    }

    /// true -> false -> true: the false resets the arm, so the later true is
    /// a fresh first observation.
    @Test("A non-divergent observation resets the arm so a later divergence starts over")
    func falseObservationResetsThenLaterTrueReArms() {
        let firstArm = clock.now
        // Intervening false observation resets the pending state.
        let afterFalse = MenuBarItemManager.confirmedDivergence(
            divergedNow: false,
            pendingSince: firstArm,
            now: firstArm.advanced(by: .seconds(1))
        )
        #expect(!afterFalse.confirmed)
        #expect(afterFalse.newPendingSince == nil)

        // The next true observation is a fresh first observation.
        let laterNow = firstArm.advanced(by: .seconds(2))
        let result = MenuBarItemManager.confirmedDivergence(
            divergedNow: true,
            pendingSince: afterFalse.newPendingSince,
            now: laterNow
        )
        #expect(!result.confirmed)
        #expect(result.newPendingSince == laterNow)
    }

    /// Beyond the staleness window the stale arm is discarded and re-armed.
    @Test("A divergence beyond the staleness window re-arms instead of confirming")
    func observationsSeparatedBeyondStalenessReArm() {
        let armedAt = clock.now
        let now = armedAt.advanced(by: .seconds(31))
        let result = MenuBarItemManager.confirmedDivergence(
            divergedNow: true,
            pendingSince: armedAt,
            now: now,
            staleness: .seconds(30)
        )
        #expect(!result.confirmed)
        #expect(result.newPendingSince == now)
    }

    /// The staleness comparison is inclusive.
    @Test("A divergence exactly at the staleness boundary still confirms")
    func observationAtExactStalenessBoundaryConfirms() {
        let armedAt = clock.now
        let now = armedAt.advanced(by: .seconds(30))
        let result = MenuBarItemManager.confirmedDivergence(
            divergedNow: true,
            pendingSince: armedAt,
            now: now,
            staleness: .seconds(30)
        )
        #expect(result.confirmed)
        #expect(result.newPendingSince == nil)
    }

    /// No divergence observed: never confirms, and any pending arm is
    /// cleared regardless of what was previously armed.
    @Test("No divergence never confirms and always clears the pending arm")
    func noDivergenceAlwaysReturnsFalseNil() {
        let now = clock.now

        let withNoPriorArm = MenuBarItemManager.confirmedDivergence(
            divergedNow: false,
            pendingSince: nil,
            now: now
        )
        #expect(!withNoPriorArm.confirmed)
        #expect(withNoPriorArm.newPendingSince == nil)

        let withPriorArm = MenuBarItemManager.confirmedDivergence(
            divergedNow: false,
            pendingSince: now.advanced(by: .seconds(-1)),
            now: now
        )
        #expect(!withPriorArm.confirmed)
        #expect(withPriorArm.newPendingSince == nil)
    }
}
