//
//  ControlItemOcclusionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Tests for the rule that turns raw `occlusionState` readings into a verdict
/// on whether a control item is being rendered.
///
/// The window server publishes occlusion asynchronously and reports everything
/// occluded while displays reconfigure, so the evaluator only moves on
/// corroborated readings taken outside the settling window.
final class ControlItemOcclusionTests: XCTestCase {
    /// A sample outside the display-change grace window, which is where all
    /// samples that are meant to count come from.
    private func settledSample(
        isOccluded: Bool,
        isInMenuBar: Bool = true
    ) -> ControlItemOcclusion.Sample {
        ControlItemOcclusion.Sample(
            isOccluded: isOccluded,
            isInMenuBar: isInMenuBar,
            secondsSinceDisplayChange: ControlItemOcclusion.displayChangeGrace + 1
        )
    }

    func testStartsUnoccluded() {
        let evaluator = ControlItemOcclusion.Evaluator()
        XCTAssertFalse(evaluator.isOccluded)
    }

    /// A single reading is not enough — that is the whole point of the type.
    func testOneOccludedSampleDoesNotChangeTheVerdict() {
        var evaluator = ControlItemOcclusion.Evaluator()
        XCTAssertNil(evaluator.evaluate(settledSample(isOccluded: true)))
        XCTAssertFalse(evaluator.isOccluded)
    }

    func testConsecutiveOccludedSamplesReportOcclusion() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        XCTAssertEqual(evaluator.evaluate(settledSample(isOccluded: true)), true)
        XCTAssertTrue(evaluator.isOccluded)
    }

    /// Once reported, the verdict stands rather than re-firing on every sample.
    func testFurtherAgreeingSamplesReportNoChange() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        XCTAssertNil(evaluator.evaluate(settledSample(isOccluded: true)))
        XCTAssertTrue(evaluator.isOccluded)
    }

    /// A lone dissenting reading between agreeing ones must not tip the verdict,
    /// which is the asynchronous-stale-read case.
    func testInterruptedRunDoesNotReportOcclusion() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        XCTAssertNil(evaluator.evaluate(settledSample(isOccluded: false)))
        XCTAssertNil(evaluator.evaluate(settledSample(isOccluded: true)))
        XCTAssertFalse(evaluator.isOccluded)
    }

    func testRecoveryRequiresConfirmationToo() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        XCTAssertTrue(evaluator.isOccluded)

        XCTAssertNil(evaluator.evaluate(settledSample(isOccluded: false)))
        XCTAssertTrue(evaluator.isOccluded)
        XCTAssertEqual(evaluator.evaluate(settledSample(isOccluded: false)), false)
        XCTAssertFalse(evaluator.isOccluded)
    }

    // MARK: Display changes

    /// Lid open/close and monitor changes report every window occluded for a
    /// moment. Those readings are discarded outright.
    func testSamplesInsideDisplayChangeGraceAreDiscarded() {
        var evaluator = ControlItemOcclusion.Evaluator()
        let noisy = ControlItemOcclusion.Sample(
            isOccluded: true,
            isInMenuBar: true,
            secondsSinceDisplayChange: 0
        )
        XCTAssertNil(evaluator.evaluate(noisy))
        XCTAssertNil(evaluator.evaluate(noisy))
        XCTAssertNil(evaluator.evaluate(noisy))
        XCTAssertFalse(evaluator.isOccluded)
    }

    /// A discarded sample must also break a run in progress, so occlusion can
    /// never be confirmed by straddling a display change.
    func testDisplayChangeBreaksAnInProgressRun() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        _ = evaluator.evaluate(
            ControlItemOcclusion.Sample(
                isOccluded: true,
                isInMenuBar: true,
                secondsSinceDisplayChange: 0
            )
        )
        XCTAssertNil(evaluator.evaluate(settledSample(isOccluded: true)))
        XCTAssertFalse(evaluator.isOccluded)
    }

    /// The boundary itself counts as settled.
    func testSampleExactlyAtGraceBoundaryCounts() {
        var evaluator = ControlItemOcclusion.Evaluator()
        let atBoundary = ControlItemOcclusion.Sample(
            isOccluded: true,
            isInMenuBar: true,
            secondsSinceDisplayChange: ControlItemOcclusion.displayChangeGrace
        )
        _ = evaluator.evaluate(atBoundary)
        XCTAssertEqual(evaluator.evaluate(atBoundary), true)
    }

    // MARK: Absence

    /// A control item the user switched off is absent, not occluded.
    func testAbsentItemIsNeverReportedOccluded() {
        var evaluator = ControlItemOcclusion.Evaluator()
        let absent = settledSample(isOccluded: true, isInMenuBar: false)
        XCTAssertNil(evaluator.evaluate(absent))
        XCTAssertNil(evaluator.evaluate(absent))
        XCTAssertFalse(evaluator.isOccluded)
    }

    /// Leaving the menu bar while occluded clears the verdict, since it can no
    /// longer be substantiated.
    func testLeavingTheMenuBarClearsAnOccludedVerdict() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        XCTAssertTrue(evaluator.isOccluded)

        XCTAssertEqual(
            evaluator.evaluate(settledSample(isOccluded: true, isInMenuBar: false)),
            false
        )
        XCTAssertFalse(evaluator.isOccluded)
    }

    /// Returning to the menu bar must earn its confirmations again rather than
    /// inheriting the run it had before it left.
    func testReturningToTheMenuBarRestartsConfirmation() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        _ = evaluator.evaluate(settledSample(isOccluded: true, isInMenuBar: false))
        XCTAssertNil(evaluator.evaluate(settledSample(isOccluded: true)))
        XCTAssertFalse(evaluator.isOccluded)
    }
}
