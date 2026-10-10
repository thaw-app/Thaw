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

    private static let stackedDisplays = [
        CGRect(x: 0, y: -1080, width: 1920, height: 1080),
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
    ]

    @Test("A neighbouring stacked display cannot validate a hidden bar", arguments: [0, 1])
    func stackedDisplayDoesNotValidateHiddenBar(targetIndex: Int) {
        let target = Self.stackedDisplays[targetIndex]
        let neighbour = Self.stackedDisplays[1 - targetIndex]
        let frames = [
            CGRect(x: 0, y: target.minY - 62, width: 1920, height: 30),
            CGRect(x: 0, y: neighbour.minY, width: 1920, height: 30),
        ]
        #expect(!MenuBarItemImageCache.isBarOnScreen(
            barFrames: frames, display: target, displays: Self.stackedDisplays
        ))
        #expect(!MenuBarItemImageCache.isBarOnScreen(
            barFrames: Array(frames.reversed()), display: target, displays: Self.stackedDisplays
        ))
    }

    @Test("A visible stacked bar stays capturable when its neighbour is hidden", arguments: [0, 1])
    func visibleStackedBarRemainsCapturable(targetIndex: Int) {
        let target = Self.stackedDisplays[targetIndex]
        let neighbour = Self.stackedDisplays[1 - targetIndex]
        #expect(MenuBarItemImageCache.isBarOnScreen(
            barFrames: [
                CGRect(x: 0, y: target.minY, width: 1920, height: 30),
                CGRect(x: 0, y: neighbour.minY - 62, width: 1920, height: 30),
            ],
            display: target, displays: Self.stackedDisplays
        ))
    }

    @Test("A missing target bar remains unknown even when another stacked bar is present", arguments: [0, 1])
    func otherDisplaysDoNotSupplyMissingGeometry(targetIndex: Int) {
        let neighbour = Self.stackedDisplays[1 - targetIndex]
        #expect(MenuBarItemImageCache.isBarOnScreen(
            barFrames: [CGRect(x: 0, y: neighbour.minY, width: 1920, height: 30)],
            display: Self.stackedDisplays[targetIndex], displays: Self.stackedDisplays
        ))
    }

    @Test("Equidistant bar geometry is unknown rather than assigned to either display", arguments: [0, 1])
    func equidistantGeometryRemainsUnknown(targetIndex: Int) {
        #expect(MenuBarItemImageCache.isBarOnScreen(
            barFrames: [CGRect(x: 0, y: -540, width: 1920, height: 30)],
            display: Self.stackedDisplays[targetIndex], displays: Self.stackedDisplays
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
