//
//  MenuBarItemImageCacheDisplayResolutionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Image cache display resolution")
struct ImageCacheDisplayResolutionTests {
    @Test("A connected preferred display is used as-is")
    func usesPreferredDisplayWhenConnected() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: 200,
            availableDisplayIDs: [100, 200, 300],
            activeMenuBarDisplayID: 300,
            mainDisplayID: 100
        )

        #expect(resolution == .init(displayID: 200, usedFallback: false))
    }

    @Test("A cached display ID from a disconnected monitor falls back instead of aborting")
    func cachedDisplayIDFromDisconnectedMonitorShouldNotAbortImageCaching() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: 999,
            availableDisplayIDs: [100, 200, 300],
            activeMenuBarDisplayID: 300,
            mainDisplayID: 100
        )

        #expect(resolution == .init(displayID: 300, usedFallback: true))
    }

    @Test("No preferred display falls back to the active one without flagging a stale fallback")
    func nilPreferredDisplayFallsBackToActiveWithoutStaleDisplayFallback() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: nil,
            availableDisplayIDs: [100, 200, 300],
            activeMenuBarDisplayID: 300,
            mainDisplayID: 100
        )

        #expect(resolution == .init(displayID: 300, usedFallback: false))
    }

    @Test("A stale preferred and active display fall back to the main display")
    func fallsBackToMainDisplayWhenPreferredAndActiveAreStale() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: 999,
            availableDisplayIDs: [100, 200, 300],
            activeMenuBarDisplayID: 888,
            mainDisplayID: 200
        )

        #expect(resolution == .init(displayID: 200, usedFallback: true))
    }

    @Test("With no preferred, active, or main match the first screen is used")
    func fallsBackToFirstScreenWhenNoPreferredActiveOrMainMatchExists() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: 999,
            availableDisplayIDs: [100, 200, 300],
            activeMenuBarDisplayID: 888,
            mainDisplayID: 777
        )

        #expect(resolution == .init(displayID: 100, usedFallback: true))
    }

    @Test("An empty screen list resolves to nothing")
    func returnsNilForEmptyScreenList() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: 999,
            availableDisplayIDs: [],
            activeMenuBarDisplayID: 888,
            mainDisplayID: 777
        )

        #expect(resolution == nil)
    }
}
