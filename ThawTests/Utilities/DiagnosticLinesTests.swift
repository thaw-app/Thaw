//
//  DiagnosticLinesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Diagnostic log lines")
struct DiagnosticLinesTests {
    @Test("A display change names each display's ID, frame and the main one")
    func screensChanged() {
        let line = DiagnosticLines.screensChanged([
            (id: 3, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isMain: true),
            (id: 1, frame: CGRect(x: -2048, y: 0, width: 2048, height: 1152), isMain: false),
        ])
        #expect(line.hasPrefix("Screen parameters changed, 2 screen(s) connected: "))
        #expect(line.contains("3=(0.0, 0.0, 2560.0, 1440.0) main"))
        #expect(line.contains("1=(-2048.0, 0.0, 2048.0, 1152.0)"))
        #expect(!line.contains("1152.0) main"))
    }

    @Test("A boundary repair line carries the frames it compared")
    func boundaryRepair() {
        let line = DiagnosticLines.boundaryRepair(
            item: "Little Snitch", itemX: 1478, section: "hidden section",
            hiddenDividerX: 1686.5, alwaysHiddenDividerX: 1685.5, revealed: "hidden section"
        )
        #expect(line.contains("Little Snitch at x=1478.0 is not in hidden section"))
        #expect(line.contains("hidden divider x=1686.5"))
        #expect(line.contains("always hidden x=1685.5"))
    }

    @Test("Without Always Hidden the line says none")
    func boundaryRepairWithoutAlwaysHidden() {
        let line = DiagnosticLines.boundaryRepair(
            item: "A", itemX: 1, section: "hidden section",
            hiddenDividerX: 2, alwaysHiddenDividerX: nil, revealed: "hidden section"
        )
        #expect(line.contains("always hidden x=none"))
    }

    @Test("Layout tiles list every tile and the ones without a picture")
    func layoutTiles() {
        let line = DiagnosticLines.layoutTiles(
            section: "visible section",
            tiles: [(name: "Clock", hasPicture: false), (name: "Siri", hasPicture: true), (name: "Home", hasPicture: false)]
        )
        #expect(line == "layout tiles (visible section): 3 [Clock, Siri, Home]; no picture: [Clock, Home]")
    }
}

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
