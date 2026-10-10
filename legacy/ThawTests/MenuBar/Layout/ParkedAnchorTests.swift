//
//  ParkedAnchorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Keeps a parked off-screen item from being used as the H_ctrl drag anchor.
///
/// At launch hidden items are parked thousands of points left of the display.
/// Picking one (such as `ai.elementlabs.lmstudio:Item-0` at minX -4222) failed all
/// 8 retries, each briefly pulling the divider on-screen, and seized the cursor
/// (#881). Parked items are excluded so the per-item LCS pass runs instead.
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

    /// With every candidate parked the anchor is nil and the per-item LCS pass takes over.
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
        // Only hidden items are movable, and all are parked, so the on-screen set is empty.
        let liveMovableUIDs: Set<String> = []
        let anchor = LayoutSolver.planHiddenDividerAnchor(
            desiredHidden: desiredHidden,
            desiredVisible: desiredVisible,
            liveMovableUIDs: liveMovableUIDs
        )
        #expect(anchor == nil)
    }

    /// An on-screen item wins over parked items earlier in the list.
    @Test("Anchor prefers an on-screen item over an earlier parked item")
    func anchorPrefersOnScreenOverParked() {
        let desiredHidden = [
            "ai.elementlabs.lmstudio:Item-0", // parked
            "com.adobe.acc.AdobeCreativeCloud:Item-0", // on-screen
        ]
        let desiredVisible: [String] = []
        // The call site already excludes the parked item.
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

/// Pins where ``LayoutSolver/isOnScreen(bounds:screenFrames:)`` measures.
///
/// A collapsed hidden divider is 5000 points wide, so its center sits 2500 points
/// right of the divider. On a three-display setup that point hit a screen while
/// the divider was parked at -3871, so the parked-drag guard let H_ctrl through
/// and it swept visible into hidden (#958).
@Suite("Off-screen is measured at the leading edge")
struct LeadingEdgeOnScreenTests {
    /// Built-in display at the origin, externals to its left and below.
    private static let screenFrames = [
        CGRect(x: 0, y: 0, width: 1728, height: 1117),
        CGRect(x: -2560, y: -300, width: 2560, height: 1440),
        CGRect(x: 0, y: -1080, width: 1920, height: 1080),
    ]

    @Test("A parked 5000-wide divider is off-screen even though its center is not")
    func parkedWideDividerIsOffScreen() {
        let divider = CGRect(x: -3871, y: 0, width: 5000, height: 33)
        #expect(Self.screenFrames.contains { $0.contains(CGPoint(x: divider.midX, y: divider.midY)) })
        #expect(!LayoutSolver.isOnScreen(bounds: divider, screenFrames: Self.screenFrames))
    }

    @Test("A 5000-wide divider sitting on the bar is on-screen")
    func seatedWideDividerIsOnScreen() {
        // Same width, not parked: the drag can land.
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
