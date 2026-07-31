//
//  CustomTooltipPanelTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Pinned to the main actor and serialized: the first case reaches the
/// `CustomTooltipPanel.shared` singleton and builds a real `IceBarPanel`,
/// so the cases must not overlap in-process.
@MainActor
@Suite("Custom tooltip panel", .serialized)
struct CustomTooltipPanelTests {
    @Test("The tooltip panel sits above the Thaw Bar")
    func tooltipAppearsAboveIceBar() {
        let iceBar = IceBarPanel()
        let tooltip = CustomTooltipPanel.shared

        #expect(
            tooltip.level.rawValue > iceBar.level.rawValue,
            "Tooltips must be above the Thaw Bar so grid items cannot obscure them"
        )
    }

    // MARK: - placementOrigin

    private let panelSize = NSSize(width: 60, height: 20)

    @Test("A placement inside a screen sits below the point and within the visible frame")
    func placementOriginInsideScreenIsBelowPointAndWithinVisibleFrame() throws {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let point = NSPoint(x: 700, y: 500)

        let origin = CustomTooltipPanel.placementOrigin(
            for: panelSize,
            near: point,
            screens: [(frame: screenFrame, visibleFrame: visibleFrame)],
            preferred: nil
        )

        let unwrapped = try #require(origin)
        #expect(visibleFrame.contains(NSRect(origin: unwrapped, size: panelSize)))
        #expect(unwrapped.y < point.y, "Tooltip should be placed below the point")
    }

    @Test("A point outside every screen yields no placement")
    func placementOriginOutsideAllScreensReturnsNil() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let point = NSPoint(x: 5000, y: 5000)

        let origin = CustomTooltipPanel.placementOrigin(
            for: panelSize,
            near: point,
            screens: [(frame: screenFrame, visibleFrame: visibleFrame)],
            preferred: nil
        )

        #expect(origin == nil, "A point outside every screen must not produce a placement")
    }

    @Test("A placement near the bottom edge is clamped inside the visible frame")
    func placementOriginNearBottomEdgeIsClampedInsideVisibleFrame() throws {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let point = NSPoint(x: 700, y: 30)

        let origin = CustomTooltipPanel.placementOrigin(
            for: panelSize,
            near: point,
            screens: [(frame: screenFrame, visibleFrame: visibleFrame)],
            preferred: nil
        )

        let unwrapped = try #require(origin)
        #expect(visibleFrame.contains(NSRect(origin: unwrapped, size: panelSize)))
    }

    @Test("A placement on the second screen is clamped to that screen's visible frame")
    func placementOriginOnSecondScreenClampsToSecondScreenVisibleFrame() throws {
        let firstFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let firstVisible = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let secondFrame = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let secondVisible = NSRect(x: 1440, y: 25, width: 1920, height: 1055)
        let point = NSPoint(x: 2000, y: 500)

        let origin = CustomTooltipPanel.placementOrigin(
            for: panelSize,
            near: point,
            screens: [
                (frame: firstFrame, visibleFrame: firstVisible),
                (frame: secondFrame, visibleFrame: secondVisible),
            ],
            preferred: nil
        )

        let unwrapped = try #require(origin)
        #expect(secondVisible.contains(NSRect(origin: unwrapped, size: panelSize)))
        #expect(!firstVisible.intersects(NSRect(origin: unwrapped, size: panelSize)))
    }
}
