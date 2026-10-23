//
//  MenuBarVisibilityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// A fullscreen app hides only its own display's bar, so a click there must
/// not count as a menu bar click because another display's bar is showing.
struct MenuBarVisibilityTests {
    private let left = CGRect(x: 0, y: 0, width: 2048, height: 1152)
    private let right = CGRect(x: 2048, y: 0, width: 2048, height: 1152)

    private func bar(on display: CGRect) -> CGRect {
        CGRect(x: display.minX, y: display.minY, width: display.width, height: 30)
    }

    @Test("Another display's bar does not make this display's bar visible")
    func otherDisplaysBarDoesNotCount() {
        #expect(!NSScreen.hasMenuBar(among: [bar(on: right)], on: left))
    }

    @Test("This display's bar counts")
    func ownBarCounts() {
        #expect(NSScreen.hasMenuBar(among: [bar(on: right), bar(on: left)], on: left))
    }

    @Test("No bar on screen means none is visible")
    func noBar() {
        #expect(!NSScreen.hasMenuBar(among: [], on: left))
    }

    @Test("A bar that won't report its frame still counts")
    func unknownFrameCounts() {
        #expect(NSScreen.hasMenuBar(among: [nil], on: left))
    }

    @Test("Every bar on screen belongs to some live display")
    @MainActor
    func liveBarsBelongToADisplay() {
        let anyBarOnScreen = !Bridging.getMenuBarWindowList(option: [.onScreen]).isEmpty
        #expect(!anyBarOnScreen || NSScreen.screens.contains { $0.isSystemMenuBarVisible() })
    }
}
