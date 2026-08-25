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

    @Test("An item whose leading edge is on the display is on-screen")
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

/// Pins the measurement point of ``LayoutSolver/isOnScreen(bounds:screenFrames:)``.
///
/// #958: a collapsed hidden divider is 5000 points wide, because that width is
/// what pushes the concealed items off the display. Measuring it at its center
/// therefore samples a point 2500 points right of the divider itself, and on
/// oa's three-display arrangement that point landed on a screen while the
/// divider was parked at minX -3871. The guard meant to refuse a drag from a
/// parked divider read a screen hit and let the drag through; H_ctrl travelled
/// to 1648 and swept the whole visible section into hidden.
@Suite("Off-screen is measured at the leading edge")
struct LeadingEdgeOnScreenTests {
    /// oa's arrangement: the built-in display at the origin, with externals
    /// placed left of it and below it.
    private static let screenFrames = [
        CGRect(x: 0, y: 0, width: 1728, height: 1117),
        CGRect(x: -2560, y: -300, width: 2560, height: 1440),
        CGRect(x: 0, y: -1080, width: 1920, height: 1080),
    ]

    @Test("A parked 5000-wide divider is off-screen even though its center is not")
    func parkedWideDividerIsOffScreen() {
        let divider = CGRect(x: -3871, y: 0, width: 5000, height: 33)
        // The reading that let #958 through.
        #expect(Self.screenFrames.contains { $0.contains(CGPoint(x: divider.midX, y: divider.midY)) })
        #expect(!LayoutSolver.isOnScreen(bounds: divider, screenFrames: Self.screenFrames))
    }

    @Test("A 5000-wide divider sitting on the bar is on-screen")
    func seatedWideDividerIsOnScreen() {
        // Same width, but parked nowhere: the divider is where the profile
        // wants it and the drag can land.
        let divider = CGRect(x: 743, y: 0, width: 5000, height: 33)
        #expect(LayoutSolver.isOnScreen(bounds: divider, screenFrames: Self.screenFrames))
    }

    @Test("A divider parked left of every display is off-screen")
    func parkedLeftOfAllDisplaysIsOffScreen() {
        let divider = CGRect(x: -8000, y: 0, width: 5000, height: 33)
        #expect(!LayoutSolver.isOnScreen(bounds: divider, screenFrames: Self.screenFrames))
    }

    @Test("Narrow items read the same either way")
    func narrowItemsAgree() {
        for minX in [-4222.0, -31.0, 0.0, 800.0, -2000.0] {
            let bounds = CGRect(x: minX, y: 0, width: 30, height: 22)
            let byCenter = Self.screenFrames.contains {
                $0.contains(CGPoint(x: bounds.midX, y: bounds.midY))
            }
            #expect(LayoutSolver.isOnScreen(bounds: bounds, screenFrames: Self.screenFrames) == byCenter)
        }
    }
}
