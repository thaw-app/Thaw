//
//  DisplayActivityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import CoreGraphics
import Testing
@testable import Thaw

/// A screen held across a topology change must not put the menu-bar-height
/// path into a retry loop. These lock the live-display guard.
@MainActor
struct DisplayActivityTests {
    @Test("A live display is active")
    func liveDisplayIsActive() {
        guard let screen = NSScreen.screens.first else {
            return // Headless runner: nothing to assert.
        }
        #expect(NSScreen.isDisplayActive(screen.displayID))
    }

    /// No real display can carry this ID, so the answer must be false on any
    /// arrangement.
    @Test("An impossible display ID is not active")
    func impossibleDisplayIsNotActive() {
        #expect(!NSScreen.isDisplayActive(CGDirectDisplayID(0xFFFF_FFF0)))
    }
}
