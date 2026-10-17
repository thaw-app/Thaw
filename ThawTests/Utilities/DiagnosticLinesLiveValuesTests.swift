//
//  DiagnosticLinesLiveValuesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Diagnostic lines from live values")
@MainActor
struct DiagnosticLinesLiveValuesTests {
    private static func item(_ title: String, x: CGFloat, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID, ownerPID: 100, sourcePID: 200,
            bounds: CGRect(x: x, y: 3, width: 20, height: 24), title: title, isOnScreen: true
        )
    }

    @Test("A display change lists each connected screen and marks the one with the menu bar as main")
    func screensChanged() throws {
        let screen = try #require(NSScreen.screens.first)
        let line = DiagnosticLines.screensChanged([screen], mainDisplayID: screen.displayID)
        #expect(line.hasPrefix("Screen parameters changed, 1 screen(s) connected: "))
        #expect(line.hasSuffix(" main"))
        let other = DiagnosticLines.screensChanged([screen], mainDisplayID: screen.displayID &+ 1)
        #expect(!other.hasSuffix(" main"))
        let all = DiagnosticLines.screensChanged(NSScreen.screens)
        #expect(all.hasPrefix("Screen parameters changed, \(NSScreen.screens.count) screen(s) connected: "))
    }

    @Test("A boundary repair reads the item and divider positions from the items")
    func boundaryRepair() {
        let pair = ControlItemPair(
            hidden: Self.item("Hidden", x: 990, windowID: 2),
            alwaysHidden: Self.item("AlwaysHidden", x: 790, windowID: 3)
        )
        let line = DiagnosticLines.boundaryRepair(
            Self.item("App", x: 1190, windowID: 1),
            section: .hidden,
            controlItems: pair,
            revealed: .visible
        )
        #expect(line.contains("at x=1200.0"))
        #expect(line.contains("hidden divider x=1000.0"))
        #expect(line.contains("always hidden x=800.0"))
    }
}
