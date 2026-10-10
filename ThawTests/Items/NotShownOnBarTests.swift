//
//  NotShownOnBarTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Geometry identifies items assigned Visible that macOS is not drawing.
struct NotShownOnBarTests {
    private func item(_ title: String, x: CGFloat, y: CGFloat = 3, width: CGFloat = 24, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: y, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("an item on a seat of its own is shown")
    func ownSeatIsShown() {
        let a = item("A", x: 1600, windowID: 1)
        let b = item("B", x: 1630, windowID: 2)
        #expect(!MenuBarItemManager.looksNotShown(a, among: [a, b]))
    }

    @Test("an item reporting another item's seat is not shown")
    func sharedSeatIsNotShown() {
        let under = item("Under", x: 1747, width: 25, windowID: 1)
        let over = item("Over", x: 1745, width: 27, windowID: 2)
        #expect(MenuBarItemManager.looksNotShown(under, among: [under, over]))
    }

    @Test("an item below the bar is not shown")
    func belowTheBarIsNotShown() {
        let lost = item("Lost", x: 1600, y: 1157, windowID: 1)
        #expect(MenuBarItemManager.looksNotShown(lost, among: [lost]))
    }

    @Test("an item with no size is not shown")
    func zeroSizeIsNotShown() {
        let flat = item("Flat", x: 1600, width: 0, windowID: 1)
        #expect(MenuBarItemManager.looksNotShown(flat, among: [flat]))
    }
}
