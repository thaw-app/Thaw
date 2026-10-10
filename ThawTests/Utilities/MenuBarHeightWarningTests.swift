//
//  MenuBarHeightWarningTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@Suite("Missing menu bar warnings")
struct MenuBarHeightWarningTests {
    @Test("A display without a bar warns once until its bar is found")
    func warnsOncePerDisplay() {
        let display: CGDirectDisplayID = 9_000_001
        defer { NSScreen.noteMenuBarFound(on: display) }

        #expect(NSScreen.shouldWarnMissingMenuBar(on: display))
        #expect(!NSScreen.shouldWarnMissingMenuBar(on: display))
        NSScreen.noteMenuBarFound(on: display)
        #expect(NSScreen.shouldWarnMissingMenuBar(on: display))
    }
}
