//
//  StaleDestinationGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Abandons a move whose target has moved out from under it.
///
/// Otherwise every attempt drags against fresh geometry and lands somewhere
/// new, so failed batches leave a different arrangement each pass and the bar
/// walks instead of converging (#900).
@Suite("Stale destination gate")
struct StaleDestinationGateTests {
    /// A target measured at -4222 then 794 on a 1512 pt display; all eight attempts
    /// went to re-dragging against it (#881).
    @Test("The observed coordinate-space swing trips the gate")
    func observedSwingTripsTheGate() {
        #expect(
            MenuBarItemManager.destinationIsStale(
                plannedTargetMinX: -4222,
                currentTargetMinX: 794,
                displayWidth: 1512
            )
        )
    }

    /// Landing beside the target pushes it by about one item width; that is a
    /// successful drag, not the bar rearranging.
    @Test("A reflow of one item width does not trip the gate")
    func itemWidthReflowIsNotStale() {
        #expect(
            !MenuBarItemManager.destinationIsStale(
                plannedTargetMinX: 832,
                currentTargetMinX: 870,
                displayWidth: 1512
            )
        )
    }

    /// An unmoved target means the item simply missed, which still deserves retries.
    @Test("An unmoved target does not trip the gate")
    func unmovedTargetIsNotStale() {
        #expect(
            !MenuBarItemManager.destinationIsStale(
                plannedTargetMinX: 640,
                currentTargetMinX: 640,
                displayWidth: 1512
            )
        )
    }

    /// The target shifts either way depending on which side the item was dropped.
    @Test("The gate is symmetric in direction")
    func gateIsSymmetric() {
        let forward = MenuBarItemManager.destinationIsStale(
            plannedTargetMinX: 0,
            currentTargetMinX: 2000,
            displayWidth: 1512
        )
        let backward = MenuBarItemManager.destinationIsStale(
            plannedTargetMinX: 2000,
            currentTargetMinX: 0,
            displayWidth: 1512
        )
        #expect(forward == backward)
        #expect(forward)
    }

    /// Exclusive threshold: exactly one display width is still recoverable.
    @Test("A shift of exactly one display width is not stale")
    func exactBoundaryIsNotStale() {
        #expect(
            !MenuBarItemManager.destinationIsStale(
                plannedTargetMinX: 0,
                currentTargetMinX: 1512,
                displayWidth: 1512
            )
        )
        #expect(
            MenuBarItemManager.destinationIsStale(
                plannedTargetMinX: 0,
                currentTargetMinX: 1513,
                displayWidth: 1512
            )
        )
    }

    /// The same absolute shift can be stale on one bar and ordinary on a wider one.
    @Test("The threshold scales with the display")
    func thresholdScalesWithDisplay() {
        #expect(
            MenuBarItemManager.destinationIsStale(
                plannedTargetMinX: 0,
                currentTargetMinX: 1600,
                displayWidth: 1512
            )
        )
        #expect(
            !MenuBarItemManager.destinationIsStale(
                plannedTargetMinX: 0,
                currentTargetMinX: 1600,
                displayWidth: 3440
            )
        )
    }

    // MARK: - MenuBarItemManager.targetIsRetreating

    /// An anchor driven from 1682 to 1650 over five attempts while the item sat at
    /// 1683 (#924, #927). Each step is below the display-width threshold. When the
    /// anchor is a divider, this ends in a zero-width hidden section that stops persisting.
    @Test("An anchor retreating on every attempt is caught")
    func retreatingAnchorIsCaught() {
        #expect(MenuBarItemManager.targetIsRetreating(recentTargetMinX: [1682, 1677, 1664, 1653, 1650]))
    }

    /// Landing beside a target nudges it by about one item width; one step proves nothing.
    @Test("A single nudge is not a retreat")
    func singleNudgeIsNotARetreat() {
        #expect(!MenuBarItemManager.targetIsRetreating(recentTargetMinX: [1682, 1648]))
    }

    /// Two steps are short of the run length.
    @Test("Two steps are below the run length")
    func twoStepsAreBelowRunLength() {
        #expect(!MenuBarItemManager.targetIsRetreating(recentTargetMinX: [1682, 1677, 1664]))
    }

    /// Direction matters, not distance: an anchor jittering back and forth is reflow.
    @Test("A jittering anchor is not retreating")
    func jitteringAnchorIsNotRetreating() {
        #expect(!MenuBarItemManager.targetIsRetreating(recentTargetMinX: [1682, 1677, 1684, 1679, 1686]))
    }

    /// Rightward is equally a retreat.
    @Test("Retreat is direction-agnostic")
    func retreatIsDirectionAgnostic() {
        #expect(MenuBarItemManager.targetIsRetreating(recentTargetMinX: [100, 110, 125, 140]))
    }

    /// Zero deltas are neither direction, so a move that needs another attempt gets one.
    @Test("A stationary anchor is not retreating")
    func stationaryAnchorIsNotRetreating() {
        #expect(!MenuBarItemManager.targetIsRetreating(recentTargetMinX: [1682, 1682, 1682, 1682]))
    }

    /// Degenerate inputs never abandon a move.
    @Test("Short histories never trip the guard", arguments: [[CGFloat](), [1682], [1682, 1677]])
    func shortHistoriesNeverTrip(history: [CGFloat]) {
        #expect(!MenuBarItemManager.targetIsRetreating(recentTargetMinX: history))
    }
}
