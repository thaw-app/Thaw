//
//  ParkedAnchorTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Pins the on-screen check that prevents a parked off-screen item from being
/// used as the H_ctrl drag anchor.
///
/// #881's remaining storm on the `fec231c` build: at launch the hidden
/// section's items are parked thousands of points left of the display by the
/// control item's collapse. `planHiddenDividerAnchor` picked the first
/// desired-hidden item (e.g. `ai.elementlabs.lmstudio:Item-0` at
/// `minX=-4222`) as the anchor, the H_ctrl drag failed all 8 retries — each
/// attempt briefly brought the divider on-screen (icons disappeared/reappeared)
/// then snapped back to the parked zone — and the user saw a cursor seizure.
///
/// The fix excludes parked items from the anchor candidate set, so the
/// per-item LCS pass (which successfully repositions items one-by-one) runs
/// instead of the futile boundary move.
@Suite("Parked anchor exclusion")
struct ParkedAnchorTests {
    private static let display = CGRect(x: 0, y: 0, width: 1728, height: 1120)
    private static let screenFrames = [display]

    // MARK: - isOnScreen

    @Test("An item whose center is on the display is on-screen")
    func onScreenItemIsOnScreen() {
        let bounds = CGRect(x: 800, y: 0, width: 30, height: 22)
        #expect(LayoutSolver.isOnScreen(bounds: bounds, screenFrames: Self.screenFrames))
    }

    @Test("An item at the left edge of the display is on-screen")
    func leftEdgeItemIsOnScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 30, height: 22)
        #expect(LayoutSolver.isOnScreen(bounds: bounds, screenFrames: Self.screenFrames))
    }

    @Test("An item parked thousands of points left of the display is not on-screen")
    func parkedItemIsNotOnScreen() {
        let bounds = CGRect(x: -4222, y: 0, width: 30, height: 22)
        #expect(!LayoutSolver.isOnScreen(bounds: bounds, screenFrames: Self.screenFrames))
    }

    @Test("An item parked at typical hidden section offset is not on-screen")
    func typicalParkedOffsetIsNotOnScreen() {
        let bounds = CGRect(x: -3526, y: 0, width: 30, height: 22)
        #expect(!LayoutSolver.isOnScreen(bounds: bounds, screenFrames: Self.screenFrames))
    }

    @Test("An item just left of the display is not on-screen")
    func justOffLeftEdgeIsNotOnScreen() {
        let bounds = CGRect(x: -31, y: 0, width: 30, height: 22)
        #expect(!LayoutSolver.isOnScreen(bounds: bounds, screenFrames: Self.screenFrames))
    }

    @Test("An item on a secondary display above the main one is on-screen")
    func secondaryDisplayItemIsOnScreen() {
        let secondary = CGRect(x: 0, y: -1120, width: 1728, height: 1120)
        let bounds = CGRect(x: 800, y: -1100, width: 30, height: 22)
        #expect(LayoutSolver.isOnScreen(bounds: bounds, screenFrames: [Self.display, secondary]))
    }

    @Test("An item on no screen (empty screen frames) is not on-screen")
    func noScreensMeansNotOnScreen() {
        let bounds = CGRect(x: 800, y: 0, width: 30, height: 22)
        #expect(!LayoutSolver.isOnScreen(bounds: bounds, screenFrames: []))
    }

    // MARK: - planHiddenDividerAnchor with parked exclusions

    /// The #881 scenario: all desired-hidden items are parked. The planner
    /// returns nil when the only movable candidates are off-screen, so the
    /// H_ctrl boundary move is skipped and the per-item LCS pass handles it.
    @Test("Anchor is nil when all desired-hidden movables are parked")
    func anchorIsNilWhenAllHiddenMovablesAreParked() {
        let desiredHidden = [
            "ai.elementlabs.lmstudio:Item-0",
            "com.adobe.acc.AdobeCreativeCloud:Item-0",
        ]
        let desiredVisible = [
            "com.apple.controlcenter:Clock",
            "com.apple.controlcenter:WiFi",
        ]
        // Only the hidden items are movable; system items in visible are not.
        // All are parked, so none appear in the on-screen movable set.
        let liveMovableUIDs: Set<String> = []
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: desiredHidden,
            desiredVisible: desiredVisible,
            liveMovableUIDs: liveMovableUIDs
        )
        #expect(anchor == nil)
    }

    /// When one desired-hidden item is on-screen, it is picked over parked
    /// items earlier in the list — the planner skips the parked ones.
    @Test("Anchor prefers an on-screen item over an earlier parked item")
    func anchorPrefersOnScreenOverParked() {
        let desiredHidden = [
            "ai.elementlabs.lmstudio:Item-0", // parked
            "com.adobe.acc.AdobeCreativeCloud:Item-0", // on-screen
        ]
        let desiredVisible: [String] = []
        // Only the on-screen item is in the movable set (parked one excluded
        // at the call site).
        let liveMovableUIDs: Set = ["com.adobe.acc.AdobeCreativeCloud:Item-0"]
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: desiredHidden,
            desiredVisible: desiredVisible,
            liveMovableUIDs: liveMovableUIDs
        )
        #expect(anchor != nil)
        guard case let .rightOf(uid) = anchor else {
            Issue.record("expected .rightOf")
            return
        }
        #expect(uid == "com.adobe.acc.AdobeCreativeCloud:Item-0")
    }
}
