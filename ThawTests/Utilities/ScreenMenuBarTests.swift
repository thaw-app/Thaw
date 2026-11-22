//
//  ScreenMenuBarTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
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

struct MenuBarDisplayCacheTests {
    private let oldFrame = CGRect(x: 2560, y: 290, width: 500, height: 34)

    @Test("Rearranging connected displays drops app-menu frames and heights")
    func rearrangementInvalidatesGeometry() {
        var cache = MenuBarDisplayCache()
        cache.applicationDidChange(to: 7)
        cache.storeMenuFrame(oldFrame, for: 2, generation: cache.generation)
        cache.storeHeight(34, for: 2, generation: cache.generation)
        cache.removeDisconnectedDisplays(keeping: [1, 2])
        #expect(cache.menuFrames[2] == oldFrame)
        #expect(cache.menuBarHeights[2] == 34)
        cache.geometryDidChange()
        cache.applicationDidChange(to: 7)
        #expect(cache.menuFrames.isEmpty)
        #expect(cache.menuBarHeights.isEmpty)
        let newFrame = CGRect(x: -1710, y: 290, width: 500, height: 34)
        cache.storeMenuFrame(newFrame, for: 2, generation: cache.generation)
        #expect(cache.menuFrames[2] == newFrame)
    }

    @Test("Reads started before a topology or menu-owner change cannot repopulate the cache")
    func staleReadsAreRejected() {
        var cache = MenuBarDisplayCache()
        let oldGeneration = cache.generation
        cache.geometryDidChange()
        cache.storeMenuFrame(oldFrame, for: 2, generation: oldGeneration)
        let stored = cache.storeHeight(34, for: 2, generation: oldGeneration)
        #expect(!stored)
        #expect(cache.menuFrames.isEmpty)
        #expect(cache.menuBarHeights.isEmpty)
        let beforeAppChange = cache.generation
        cache.applicationDidChange(to: 8)
        cache.storeMenuFrame(oldFrame, for: 2, generation: beforeAppChange)
        #expect(cache.menuFrames.isEmpty)
        cache.storeMenuFrame(oldFrame, for: 2, generation: cache.generation)
        cache.storeHeight(34, for: 2, generation: cache.generation)
        cache.removeDisconnectedDisplays(keeping: [1])
        #expect(cache.menuFrames.isEmpty)
        #expect(cache.menuBarHeights.isEmpty)
    }
}

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

/// A fullscreen app hides only its own display's bar, so a click there must
/// not count as a menu bar click because another display's bar is showing.
struct MenuBarVisibilityTests {
    @Test("Only this display's bar, or a bar that won't report its frame, makes this display's bar visible", arguments: [
        ([CGRect(x: 2048, y: 0, width: 2048, height: 30)], false),
        ([CGRect(x: 2048, y: 0, width: 2048, height: 30), CGRect(x: 0, y: 0, width: 2048, height: 30)], true),
        ([], false),
        ([nil], true),
    ] as [([CGRect?], Bool)])
    func barOnThisDisplay(bars: [CGRect?], visible: Bool) {
        #expect(NSScreen.hasMenuBar(among: bars, on: CGRect(x: 0, y: 0, width: 2048, height: 1152)) == visible)
    }

    @Test("Every bar on screen belongs to some live display")
    @MainActor
    func liveBarsBelongToADisplay() {
        let anyBarOnScreen = !Bridging.getMenuBarWindowList(option: [.onScreen]).isEmpty
        #expect(!anyBarOnScreen || NSScreen.screens.contains { $0.isSystemMenuBarVisible() })
    }
}

/// A screen held across a topology change must not put the menu bar height read into a retry loop.
@MainActor
struct DisplayActivityTests {
    @Test("A live display is active")
    func liveDisplayIsActive() {
        guard let screen = NSScreen.screens.first else {
            return // Headless runner: nothing to assert.
        }
        #expect(NSScreen.isDisplayActive(screen.displayID))
    }

    @Test("An impossible display ID is not active")
    func impossibleDisplayIsNotActive() {
        #expect(!NSScreen.isDisplayActive(CGDirectDisplayID(0xFFFF_FFF0)))
    }
}

/// How a change is classified is pinned in EnvironmentSnapshotTests.
@Suite("Display arrangement")
struct DisplayArrangementTests {
    @Test("The current arrangement names a main display exactly when it has displays")
    @MainActor
    func currentReading() {
        let reading = DisplayArrangement.current
        #expect(reading.frames.isEmpty == (reading.mainDisplayID == nil))
    }
}
