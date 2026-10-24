//
//  ClickSafetyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Thaw

struct ClickSafetyTests {
    private static let screens = [
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: 2560, y: 290, width: 1710, height: 1107),
    ]

    @Test("Synthetic clicks follow the pointer only in its display's top bar")
    func clickUsesTopBar() {
        let bounds = CGRect(x: 2400, y: 5, width: 24, height: 24)
        let lower = Self.screens[1]
        for y: CGFloat in [290, 307, 324] {
            #expect(ClickTargetCheck.clickPoint(
                for: bounds, pointer: CGPoint(x: 4100, y: y), display: lower,
                menuBarHeight: 34, displays: Self.screens
            ) == CGPoint(x: 4122, y: 307))
        }
        for point in [CGPoint(x: 4100, y: 325), CGPoint(x: 4100, y: 1390), CGPoint(x: 2000, y: 307)] {
            #expect(ClickTargetCheck.clickPoint(
                for: bounds, pointer: point, display: lower,
                menuBarHeight: 34, displays: Self.screens
            ) == CGPoint(x: 2412, y: 17))
        }
    }

    @Test("A lower bar is safe to click, while frames below it and host windows are refused")
    func lowerDisplayClickSafety() {
        let seated = CGRect(x: 3600, y: 295, width: 24, height: 24)
        let parked = CGRect(x: 3600, y: 1068, width: 24, height: 24)
        let host = CGRect(x: 2560, y: 295, width: 1000, height: 24)
        #expect(ClickTargetCheck.rejection(for: seated, barWidth: 1710, displays: Self.screens) == nil)
        #expect(ClickTargetCheck.rejection(for: parked, barWidth: 1710, displays: Self.screens) == .offBar)
        #expect(ClickTargetCheck.rejection(for: host, barWidth: 1710, displays: Self.screens) == .tooWide)
    }

    @Test
    func `a seated item frame is clicked`() {
        #expect(ClickTargetCheck.rejection(for: CGRect(x: 1400, y: 0, width: 24, height: 30), barWidth: 1512, displays: Self.screens) == nil)
    }

    @Test
    func `parked, off-bar, empty and too-wide frames are refused`() {
        #expect(ClickTargetCheck.rejection(for: CGRect(x: -1, y: 0, width: 24, height: 30), barWidth: 1512, displays: Self.screens) == .parked)
        #expect(ClickTargetCheck.rejection(for: CGRect(x: 7, y: 1068, width: 24, height: 30), barWidth: 1512, displays: Self.screens) == .offBar)
        #expect(ClickTargetCheck.rejection(for: .zero, barWidth: 1512, displays: Self.screens) == .empty)
        #expect(ClickTargetCheck.rejection(for: .null, barWidth: 1512, displays: Self.screens) == .empty)
        #expect(ClickTargetCheck.rejection(for: CGRect(x: 0, y: 0, width: 1512, height: 30), barWidth: 1512, displays: Self.screens) == .tooWide)
    }

    @Test
    func `a wide status item with text is clicked, and the width check needs a bar`() {
        let textItem = CGRect(x: 900, y: 0, width: 320, height: 30)
        #expect(ClickTargetCheck.rejection(for: textItem, barWidth: 1512, displays: Self.screens) == nil)
        #expect(ClickTargetCheck.rejection(for: CGRect(x: 0, y: 0, width: 3000, height: 30), barWidth: 0, displays: Self.screens) == nil)
    }

    @Test
    func `the width check uses the bar the frame sits on`() {
        let displays = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 800, height: 600)]
        let textItem = CGRect(x: 900, y: 0, width: 450, height: 30)
        #expect(ClickTargetCheck.barWidth(for: textItem, displays: displays) == 1512)
        #expect(ClickTargetCheck.rejection(for: textItem, barWidth: ClickTargetCheck.barWidth(for: textItem, displays: displays), displays: displays) == nil)
        #expect(ClickTargetCheck.barWidth(for: CGRect(x: 1700, y: 0, width: 24, height: 30), displays: displays) == 800)
        #expect(ClickTargetCheck.barWidth(for: CGRect(x: -400, y: 0, width: 24, height: 30), displays: displays) == 1512)
        #expect(ClickTargetCheck.barWidth(for: textItem, displays: []) == 0)
    }

    @MainActor
    @Test
    func `the live bar width comes from the attached displays`() {
        let frames = NSScreen.screens.map(\.frame)
        let bounds = CGRect(x: frames.first?.midX ?? 0, y: 0, width: 24, height: 30)
        #expect(ClickTargetCheck.barWidth(for: bounds) == ClickTargetCheck.barWidth(for: bounds, displays: frames))
    }

    @Test
    func `the budget allows a burst of clicks, then refuses until the window passes`() {
        var budget = SyntheticClickBudget()
        let start = ContinuousClock.now
        for offset in 0 ..< SyntheticClickBudget.limit {
            let taken = budget.take(now: start + .milliseconds(offset))
            #expect(taken)
        }
        let overBudget = budget.take(now: start + .seconds(1))
        #expect(!overBudget)
        let afterWindow = budget.take(now: start + SyntheticClickBudget.window + .milliseconds(1))
        #expect(afterWindow)
    }
}
