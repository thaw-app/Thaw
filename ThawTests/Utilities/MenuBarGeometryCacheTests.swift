//
//  MenuBarGeometryCacheTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// The per-display menu bar cache only reads the window list; nothing here changes the bar.
@MainActor
@Suite("Menu bar geometry cache", .serialized)
struct MenuBarGeometryCacheTests {
    /// The main screen's live bar height, which fills the cache, or nil on a machine without a bar window.
    private func cachedMainHeight() -> CGFloat? {
        NSScreen.main?.getMenuBarHeight()
    }

    @Test("A geometry change empties the height cache")
    func geometryChangeEmptiesCache() throws {
        try #require(cachedMainHeight() != nil, "The test needs a menu bar window on the main display")
        #expect(NSScreen.tallestCachedMenuBarHeight != nil)
        NSScreen.invalidateMenuBarGeometryCache()
        #expect(NSScreen.tallestCachedMenuBarHeight == nil)
    }

    @Test("Cleaning up disconnected displays keeps the connected display's height")
    func cleanupKeepsConnectedDisplays() throws {
        let height = try #require(cachedMainHeight(), "The test needs a menu bar window on the main display")
        NSScreen.cleanupDisconnectedDisplayCaches()
        #expect(NSScreen.tallestCachedMenuBarHeight == height)
    }

    @Test("The screen with the mouse is the one whose frame holds the pointer")
    func screenWithMouseHoldsPointer() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screenWithMouse else {
            #expect(!NSScreen.screens.contains { $0.frame.contains(pointer) })
            return
        }
        #expect(screen.frame.contains(pointer))
    }
}
