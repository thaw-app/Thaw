//
//  MenuBarItemHeightCeilingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Pins the height ceiling the AX walk holds extras-bar children to.
@Suite("Menu bar item height ceiling")
struct MenuBarItemHeightCeilingTests {
    @Test("A bar at or under 40 pt keeps the 40 pt ceiling", arguments: [nil, 24.0, 33.0, 39.0] as [CGFloat?])
    func standardBarsKeepTheFloor(menuBarHeight: CGFloat?) {
        #expect(MenuBarItemAXProvider.maxItemHeight(menuBarHeight: menuBarHeight) == 40)
    }

    /// 64 px of notched bar on a 3456 px panel scaled to 2177 pt.
    @Test("A notched bar taller than 40 pt admits its full-height system items")
    func tallNotchedBarAdmitsSystemItems() {
        let barHeight: CGFloat = 64 / (3456 / 2177)
        let ceiling = MenuBarItemAXProvider.maxItemHeight(menuBarHeight: barHeight)
        #expect(barHeight > 40)
        #expect(barHeight <= ceiling)
    }

    @Test("Popovers and panels stay above the ceiling")
    func popoversStayRejected() {
        let ceiling = MenuBarItemAXProvider.maxItemHeight(menuBarHeight: 42)
        #expect(ceiling < 60)
    }
}
