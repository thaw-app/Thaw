//
//  ControlItemOcclusionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Tests for the rule that turns raw `occlusionState` readings into a verdict
/// on whether a control item is being rendered.
///
/// The window server publishes occlusion asynchronously and reports everything
/// occluded while displays reconfigure, so the evaluator only moves on
/// corroborated readings taken outside the settling window.
@Suite("Control item occlusion")
struct ControlItemOcclusionTests {
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

    @Test("A fresh evaluator starts unoccluded")
    func startsUnoccluded() {
        let evaluator = ControlItemOcclusion.Evaluator()
        #expect(!evaluator.isOccluded)
    }

    /// A single reading is not enough — that is the whole point of the type.
    @Test("One occluded sample does not change the verdict")
    func oneOccludedSampleDoesNotChangeTheVerdict() {
        var evaluator = ControlItemOcclusion.Evaluator()
        #expect(evaluator.evaluate(settledSample(isOccluded: true)) == nil)
        #expect(!evaluator.isOccluded)
    }

    @Test("Consecutive occluded samples report occlusion")
    func consecutiveOccludedSamplesReportOcclusion() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        #expect(evaluator.evaluate(settledSample(isOccluded: true)) == true)
        #expect(evaluator.isOccluded)
    }

    /// Once reported, the verdict stands rather than re-firing on every sample.
    @Test("Further agreeing samples report no change")
    func furtherAgreeingSamplesReportNoChange() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        #expect(evaluator.evaluate(settledSample(isOccluded: true)) == nil)
        #expect(evaluator.isOccluded)
    }

    /// A lone dissenting reading between agreeing ones must not tip the verdict,
    /// which is the asynchronous-stale-read case.
    @Test("An interrupted run does not report occlusion")
    func interruptedRunDoesNotReportOcclusion() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        #expect(evaluator.evaluate(settledSample(isOccluded: false)) == nil)
        #expect(evaluator.evaluate(settledSample(isOccluded: true)) == nil)
        #expect(!evaluator.isOccluded)
    }

    @Test("Recovery requires confirmation too")
    func recoveryRequiresConfirmationToo() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        #expect(evaluator.isOccluded)

        #expect(evaluator.evaluate(settledSample(isOccluded: false)) == nil)
        #expect(evaluator.isOccluded)
        #expect(evaluator.evaluate(settledSample(isOccluded: false)) == false)
        #expect(!evaluator.isOccluded)
    }

    // MARK: Display changes

    /// Lid open/close and monitor changes report every window occluded for a
    /// moment. Those readings are discarded outright.
    @Test("Samples inside the display-change grace window are discarded")
    func samplesInsideDisplayChangeGraceAreDiscarded() {
        var evaluator = ControlItemOcclusion.Evaluator()
        let noisy = ControlItemOcclusion.Sample(
            isOccluded: true,
            isInMenuBar: true,
            secondsSinceDisplayChange: 0
        )
        #expect(evaluator.evaluate(noisy) == nil)
        #expect(evaluator.evaluate(noisy) == nil)
        #expect(evaluator.evaluate(noisy) == nil)
        #expect(!evaluator.isOccluded)
    }

    /// A discarded sample must also break a run in progress, so occlusion can
    /// never be confirmed by straddling a display change.
    @Test("A display change breaks an in-progress run")
    func displayChangeBreaksAnInProgressRun() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        _ = evaluator.evaluate(
            ControlItemOcclusion.Sample(
                isOccluded: true,
                isInMenuBar: true,
                secondsSinceDisplayChange: 0
            )
        )
        #expect(evaluator.evaluate(settledSample(isOccluded: true)) == nil)
        #expect(!evaluator.isOccluded)
    }

    /// The boundary itself counts as settled.
    @Test("A sample exactly at the grace boundary counts")
    func sampleExactlyAtGraceBoundaryCounts() {
        var evaluator = ControlItemOcclusion.Evaluator()
        let atBoundary = ControlItemOcclusion.Sample(
            isOccluded: true,
            isInMenuBar: true,
            secondsSinceDisplayChange: ControlItemOcclusion.displayChangeGrace
        )
        _ = evaluator.evaluate(atBoundary)
        #expect(evaluator.evaluate(atBoundary) == true)
    }

    // MARK: Absence

    /// A control item the user switched off is absent, not occluded.
    @Test("An absent item is never reported occluded")
    func absentItemIsNeverReportedOccluded() {
        var evaluator = ControlItemOcclusion.Evaluator()
        let absent = settledSample(isOccluded: true, isInMenuBar: false)
        #expect(evaluator.evaluate(absent) == nil)
        #expect(evaluator.evaluate(absent) == nil)
        #expect(!evaluator.isOccluded)
    }

    /// Leaving the menu bar while occluded clears the verdict, since it can no
    /// longer be substantiated.
    @Test("Leaving the menu bar clears an occluded verdict")
    func leavingTheMenuBarClearsAnOccludedVerdict() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        #expect(evaluator.isOccluded)

        #expect(
            evaluator.evaluate(settledSample(isOccluded: true, isInMenuBar: false)) == false
        )
        #expect(!evaluator.isOccluded)
    }

    /// Returning to the menu bar must earn its confirmations again rather than
    /// inheriting the run it had before it left.
    @Test("Returning to the menu bar restarts confirmation")
    func returningToTheMenuBarRestartsConfirmation() {
        var evaluator = ControlItemOcclusion.Evaluator()
        _ = evaluator.evaluate(settledSample(isOccluded: true))
        _ = evaluator.evaluate(settledSample(isOccluded: true, isInMenuBar: false))
        #expect(evaluator.evaluate(settledSample(isOccluded: true)) == nil)
        #expect(!evaluator.isOccluded)
    }
}
