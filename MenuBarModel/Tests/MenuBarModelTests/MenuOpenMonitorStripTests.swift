//
//  MenuOpenMonitorStripTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import MenuBarModel
import Testing

@Suite("Menu open monitor strip height")
struct MenuOpenMonitorStripTests {
    @Test("A bar that reserves room keeps that height", arguments: [24.0, 30.0, 38.0] as [CGFloat])
    func reservedHeight(reserved: CGFloat) {
        let height = MenuOpenMonitor.menuBarStripHeight(reserved: reserved, measured: 12, hasMenuBar: true)
        #expect(height == reserved)
    }

    @Test("An auto-hidden bar uses the height measured from the bar window")
    func autoHiddenBar() {
        let height = MenuOpenMonitor.menuBarStripHeight(reserved: 0, measured: 30, hasMenuBar: true)
        #expect(height == 30)
    }

    @Test("An auto-hidden bar with no measured height has no strip")
    func autoHiddenBarUnmeasured() {
        #expect(MenuOpenMonitor.menuBarStripHeight(reserved: 0, measured: nil, hasMenuBar: true) == nil)
        #expect(MenuOpenMonitor.menuBarStripHeight(reserved: 0, measured: 0, hasMenuBar: true) == nil)
    }

    @Test("A screen without a menu bar has no strip")
    func screenWithoutBar() {
        let height = MenuOpenMonitor.menuBarStripHeight(reserved: 0, measured: 30, hasMenuBar: false)
        #expect(height == nil)
    }
}
