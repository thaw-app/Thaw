//
//  StaleDestinationGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes the gate that abandons a move whose target has moved out
/// from under it.
///
/// Without it, a move whose destination has already shifted keeps its full
/// attempt budget, and every attempt drags the item against freshly measured
/// geometry. Each drag lands somewhere new, so a failed batch leaves a
/// different partial arrangement behind on each pass and the bar walks
/// instead of converging (#900).
@Suite("Stale destination gate")
struct StaleDestinationGateTests {
    /// The #881 numbers: a single move whose target was measured at -4222 on
    /// one attempt and 794 on the next, on the reporter's 1512 pt display.
    /// All eight attempts went to re-dragging against it.
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

    /// Landing beside the target pushes it over by about the moved item's
    /// width. That is the normal outcome of a successful drag and must not be
    /// mistaken for the bar rearranging.
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

    /// A target that has not moved at all is the case where the item simply
    /// missed, which still deserves its retries.
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

    /// Direction must not matter: the target can be displaced either way
    /// depending on which side of it the item was dropped.
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

    /// The threshold is exclusive, so a shift of exactly one display width is
    /// still treated as recoverable. Pinned because the boundary is the whole
    /// content of the rule.
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

    /// A wider display tolerates a proportionally wider reflow, so the same
    /// absolute shift can be stale on one bar and ordinary on another.
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

    /// The live #924/#927 sequence: an anchor driven from 1682 to 1650 over
    /// five attempts while the moved item sat at 1683 the whole time. Every
    /// step is far too small for the display-width staleness threshold, so
    /// the budget was spent walking the anchor across the bar. When the
    /// anchor is one of Thaw's dividers, repeating that across cycles ends
    /// in a zero-width hidden section and a layout that stops persisting.
    @Test("An anchor retreating on every attempt is caught")
    func retreatingAnchorIsCaught() {
        #expect(MenuBarItemManager.targetIsRetreating(recentTargetMinX: [1682, 1677, 1664, 1653, 1650]))
    }

    /// Landing beside a target legitimately nudges it by roughly the moved
    /// item's width. One step proves nothing and must not abandon the move.
    @Test("A single nudge is not a retreat")
    func singleNudgeIsNotARetreat() {
        #expect(!MenuBarItemManager.targetIsRetreating(recentTargetMinX: [1682, 1648]))
    }

    /// Two steps are still short of the run length; the guard waits for
    /// evidence rather than abandoning on the second attempt.
    @Test("Two steps are below the run length")
    func twoStepsAreBelowRunLength() {
        #expect(!MenuBarItemManager.targetIsRetreating(recentTargetMinX: [1682, 1677, 1664]))
    }

    /// Direction is what matters, not distance: an anchor jittering back and
    /// forth is reflow, not a move pushing it.
    @Test("A jittering anchor is not retreating")
    func jitteringAnchorIsNotRetreating() {
        #expect(!MenuBarItemManager.targetIsRetreating(recentTargetMinX: [1682, 1677, 1684, 1679, 1686]))
    }

    /// Rightward is equally a retreat — a left-to-right bar, or an anchor
    /// being pushed the other way, fails the same way.
    @Test("Retreat is direction-agnostic")
    func retreatIsDirectionAgnostic() {
        #expect(MenuBarItemManager.targetIsRetreating(recentTargetMinX: [100, 110, 125, 140]))
    }

    /// A stationary anchor is the healthy case: zero deltas are neither
    /// direction, so a move that simply needs another attempt gets one.
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
