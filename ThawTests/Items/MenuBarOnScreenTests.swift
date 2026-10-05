//
//  MenuBarOnScreenTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Capture skips a display whose bar is off screen")
struct MenuBarOnScreenTests {
    /// The host's bar windows as logged with focus on the first display: the second
    /// display's bar had slid 62 pt above its top edge.
    private static let barFrames = [
        CGRect(x: 0, y: 0, width: 1920, height: 30),
        CGRect(x: 1920, y: -62, width: 1920, height: 30),
        CGRect(x: -1728, y: 0, width: 1728, height: 33),
    ]

    @Test("A bar slid above its display is off screen")
    func slidBarIsOffScreen() {
        #expect(!MenuBarItemImageCache.isBarOnScreen(
            barFrames: Self.barFrames,
            display: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        ))
    }

    @Test("Bars at their display's top edge are on screen")
    func settledBarsAreOnScreen() {
        #expect(MenuBarItemImageCache.isBarOnScreen(
            barFrames: Self.barFrames,
            display: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        ))
        #expect(MenuBarItemImageCache.isBarOnScreen(
            barFrames: Self.barFrames,
            display: CGRect(x: -1728, y: 0, width: 1728, height: 1117)
        ))
    }

    @Test("Inventory refresh requests are limited to one per two seconds")
    @MainActor
    func refreshRequestsAreRateLimited() {
        let cache = MenuBarItemImageCache()
        cache.requestInventoryRefresh(reason: "test")
        let first = cache.lastInventoryRefreshRequest
        #expect(first != nil)
        cache.requestInventoryRefresh(reason: "test")
        #expect(cache.lastInventoryRefreshRequest == first)
    }

    @Test("No matching bar window does not block capture")
    func unknownGeometryCounts() {
        #expect(MenuBarItemImageCache.isBarOnScreen(
            barFrames: [],
            display: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        ))
    }
}
