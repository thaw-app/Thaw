//
//  MenuBarItemImageCacheSeamTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

final class MenuBarItemImageCacheSeamTests: XCTestCase {
    @MainActor
    func testDisplayIDFallsBackToMainDisplayWhenWindowServerHasNoActiveDisplay() {
        let windowServer = FakeWindowServerReader()
        let cache = MenuBarItemImageCache(windowServer: windowServer)

        let displayID = cache.captureDisplayID(itemCacheDisplayID: nil, mainDisplayID: 42)

        XCTAssertEqual(displayID, 42)
        XCTAssertEqual(windowServer.activeDisplayQueries, 1)
    }

    @MainActor
    func testMissingWindowBoundsReturnsNilAndRecordsTheQuery() {
        let windowServer = FakeWindowServerReader()
        let cache = MenuBarItemImageCache(windowServer: windowServer)

        XCTAssertNil(cache.liveWindowBounds(for: 7))
        XCTAssertEqual(windowServer.boundsQueries, [7])
    }

    @MainActor
    func testScriptedWindowBoundsFlowThroughTheSeam() {
        let expectedBounds = CGRect(x: 10, y: 20, width: 30, height: 40)
        let windowServer = FakeWindowServerReader(boundsByWindowID: [9: expectedBounds])
        let cache = MenuBarItemImageCache(windowServer: windowServer)

        XCTAssertEqual(cache.liveWindowBounds(for: 9), expectedBounds)
        XCTAssertEqual(windowServer.boundsQueries, [9])
    }
}

private final class FakeWindowServerReader: WindowServerReading, @unchecked Sendable {
    var displayID: CGDirectDisplayID?
    var boundsByWindowID: [CGWindowID: CGRect]
    private(set) var activeDisplayQueries = 0
    private(set) var boundsQueries: [CGWindowID] = []

    init(
        displayID: CGDirectDisplayID? = nil,
        boundsByWindowID: [CGWindowID: CGRect] = [:]
    ) {
        self.displayID = displayID
        self.boundsByWindowID = boundsByWindowID
    }

    func activeMenuBarDisplayID() -> CGDirectDisplayID? {
        activeDisplayQueries += 1
        return displayID
    }

    func windowBounds(for windowID: CGWindowID) -> CGRect? {
        boundsQueries.append(windowID)
        return boundsByWindowID[windowID]
    }
}
