//
//  DivergencePersistenceGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterizes the divergence-persistence gate that decides whether a
/// divergence observation should trigger a saved-layout re-apply.
///
/// The bug (#723): a single divergent reading of
/// `currentLayoutDivergesFromSaved` can be transient — an app activating with
/// a wide application menu compresses or covers status items, shifting their
/// bounds for as long as the menu is up. Reading that as "items in the wrong
/// section" and immediately dispatching a bulk apply replays the whole
/// layout and yanks the cursor around for geometry that resolves itself once
/// the menu closes. The fix requires the same divergence to be observed on
/// two consecutive cache cycles before it is treated as confirmed.
final class DivergencePersistenceGateTests: XCTestCase {
    private let clock = ContinuousClock()

    /// First observation of a divergence: must defer (not confirmed yet) and
    /// arm the pending state to the observation time.
    func testFirstObservationDefersAndArms() {
        let now = clock.now
        let result = MenuBarItemManager.confirmedDivergence(
            divergedNow: true,
            pendingSince: nil,
            now: now
        )
        XCTAssertFalse(result.confirmed)
        XCTAssertEqual(result.newPendingSince, now)
    }

    /// A second divergent observation within the staleness window confirms
    /// and resets the pending state.
    func testSecondObservationWithinWindowConfirmsAndResets() {
        let armedAt = clock.now
        let now = armedAt.advanced(by: .seconds(5))
        let result = MenuBarItemManager.confirmedDivergence(
            divergedNow: true,
            pendingSince: armedAt,
            now: now,
            staleness: .seconds(30)
        )
        XCTAssertTrue(result.confirmed)
        XCTAssertNil(result.newPendingSince)
    }

    /// true -> false -> true: the false observation resets any pending arm,
    /// so the later true is treated as a fresh first observation (defer,
    /// re-arm), not a confirmation of the earlier one.
    func testFalseObservationResetsThenLaterTrueReArms() {
        let firstArm = clock.now
        // Intervening false observation resets the pending state.
        let afterFalse = MenuBarItemManager.confirmedDivergence(
            divergedNow: false,
            pendingSince: firstArm,
            now: firstArm.advanced(by: .seconds(1))
        )
        XCTAssertFalse(afterFalse.confirmed)
        XCTAssertNil(afterFalse.newPendingSince)

        // The next true observation is a fresh first observation.
        let laterNow = firstArm.advanced(by: .seconds(2))
        let result = MenuBarItemManager.confirmedDivergence(
            divergedNow: true,
            pendingSince: afterFalse.newPendingSince,
            now: laterNow
        )
        XCTAssertFalse(result.confirmed)
        XCTAssertEqual(result.newPendingSince, laterNow)
    }

    /// Two divergent observations separated beyond the staleness window: the
    /// stale arm is discarded and the later observation defers and re-arms
    /// rather than confirming against the too-old arm.
    func testObservationsSeparatedBeyondStalenessReArm() {
        let armedAt = clock.now
        let now = armedAt.advanced(by: .seconds(31))
        let result = MenuBarItemManager.confirmedDivergence(
            divergedNow: true,
            pendingSince: armedAt,
            now: now,
            staleness: .seconds(30)
        )
        XCTAssertFalse(result.confirmed)
        XCTAssertEqual(result.newPendingSince, now)
    }

    /// No divergence observed: never confirms, and any pending arm is
    /// cleared regardless of what was previously armed.
    func testNoDivergenceAlwaysReturnsFalseNil() {
        let now = clock.now

        let withNoPriorArm = MenuBarItemManager.confirmedDivergence(
            divergedNow: false,
            pendingSince: nil,
            now: now
        )
        XCTAssertFalse(withNoPriorArm.confirmed)
        XCTAssertNil(withNoPriorArm.newPendingSince)

        let withPriorArm = MenuBarItemManager.confirmedDivergence(
            divergedNow: false,
            pendingSince: now.advanced(by: .seconds(-1)),
            now: now
        )
        XCTAssertFalse(withPriorArm.confirmed)
        XCTAssertNil(withPriorArm.newPendingSince)
    }
}
