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
}
