//
//  MenuBarItemImageCacheDisplayResolutionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

final class ImageCacheDisplayResolutionTests: XCTestCase {
    func testUsesPreferredDisplayWhenConnected() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: 200,
            availableDisplayIDs: [100, 200, 300],
            activeMenuBarDisplayID: 300,
            mainDisplayID: 100
        )

        XCTAssertEqual(resolution, .init(displayID: 200, usedFallback: false))
    }

    func testCachedDisplayIDFromDisconnectedMonitorShouldNotAbortImageCaching() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: 999,
            availableDisplayIDs: [100, 200, 300],
            activeMenuBarDisplayID: 300,
            mainDisplayID: 100
        )

        XCTAssertEqual(resolution, .init(displayID: 300, usedFallback: true))
    }

    func testFallsBackToMainDisplayWhenPreferredAndActiveAreStale() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: 999,
            availableDisplayIDs: [100, 200, 300],
            activeMenuBarDisplayID: 888,
            mainDisplayID: 200
        )

        XCTAssertEqual(resolution, .init(displayID: 200, usedFallback: true))
    }

    func testFallsBackToFirstScreenWhenNoPreferredActiveOrMainMatchExists() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: 999,
            availableDisplayIDs: [100, 200, 300],
            activeMenuBarDisplayID: 888,
            mainDisplayID: 777
        )

        XCTAssertEqual(resolution, .init(displayID: 100, usedFallback: true))
    }

    func testReturnsNilForEmptyScreenList() {
        let resolution = MenuBarItemImageCache.resolveDisplayID(
            preferredDisplayID: 999,
            availableDisplayIDs: [],
            activeMenuBarDisplayID: 888,
            mainDisplayID: 777
        )

        XCTAssertNil(resolution)
    }
}
