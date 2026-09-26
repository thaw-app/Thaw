//
//  SelectWindowForBatchScanTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// `LayoutSolver.selectWindowForBatchScan`, which picks the window pidsBody
/// hands to pidBody. A cached window returns early and skips the AX scan, so
/// the pick must be unresolved; one scan then resolves the whole batch.
/// Guards against reverting to `windows.first`.
@Suite("Select window for batch scan")
struct SelectWindowForBatchScanTests {
    /// Only the WindowInfo fields the helper reads.
    private struct FakeWindow: Equatable {
        let windowID: CGWindowID
    }

    @Test("An empty batch selects no window")
    func emptyBatchReturnsNil() {
        let result = LayoutSolver.selectWindowForBatchScan(
            windows: [FakeWindow](),
            windowID: \.windowID,
            cachedPIDs: [:]
        )
        #expect(result == nil)
    }

    /// The steady state once every item has resolved.
    @Test("A fully cached batch selects no window")
    func allCachedReturnsNil() {
        let windows = [
            FakeWindow(windowID: 100),
            FakeWindow(windowID: 200),
            FakeWindow(windowID: 300),
        ]
        let result = LayoutSolver.selectWindowForBatchScan(
            windows: windows,
            windowID: \.windowID,
            cachedPIDs: [100: 11, 200: 22, 300: 33]
        )
        #expect(result == nil)
    }

    /// Also the session-start case, when the cache is empty.
    @Test("An unresolved first window is selected")
    func firstUnresolvedReturnsFirst() {
        let windows = [
            FakeWindow(windowID: 100),
            FakeWindow(windowID: 200),
        ]
        let result = LayoutSolver.selectWindowForBatchScan(
            windows: windows,
            windowID: \.windowID,
            cachedPIDs: [:]
        )
        #expect(result == windows[0])
    }

    /// The bug: an older resolved window leads the batch while a new app's window
    /// later in it needs the scan.
    @Test("A cached first window is skipped for the unresolved second one")
    func firstCachedSecondUnresolvedReturnsSecond() {
        let windows = [
            FakeWindow(windowID: 100), // cached
            FakeWindow(windowID: 200), // unresolved (new app)
        ]
        let result = LayoutSolver.selectWindowForBatchScan(
            windows: windows,
            windowID: \.windowID,
            cachedPIDs: [100: 11]
        )
        #expect(result == windows[1])
    }

    @Test("An unresolved last window is selected when every earlier one is cached")
    func onlyLastUnresolvedReturnsLast() {
        let windows = [
            FakeWindow(windowID: 100),
            FakeWindow(windowID: 200),
            FakeWindow(windowID: 300),
        ]
        let result = LayoutSolver.selectWindowForBatchScan(
            windows: windows,
            windowID: \.windowID,
            cachedPIDs: [100: 11, 200: 22]
        )
        #expect(result == windows[2])
    }

    /// Iteration order, not cache order, so several new widgets resolve predictably.
    @Test("Several unresolved windows select the leftmost of them")
    func multipleUnresolvedReturnsFirstUnresolved() {
        let windows = [
            FakeWindow(windowID: 100), // cached
            FakeWindow(windowID: 200), // unresolved
            FakeWindow(windowID: 300), // unresolved
            FakeWindow(windowID: 400), // cached
            FakeWindow(windowID: 500), // unresolved
        ]
        let result = LayoutSolver.selectWindowForBatchScan(
            windows: windows,
            windowID: \.windowID,
            cachedPIDs: [100: 11, 400: 44]
        )
        #expect(result == windows[1])
    }

    /// A field shape: an old resolved head, then a chronic nil-PID widget and new apps.
    @Test("A realistic mid-session batch skips its cached head")
    func realisticBatchSkipsCachedHead() {
        let windows = [
            FakeWindow(windowID: 78), // cached
            FakeWindow(windowID: 80), // chronic nil-PID
            FakeWindow(windowID: 119), // new app
            FakeWindow(windowID: 687), // new app
        ]
        let result = LayoutSolver.selectWindowForBatchScan(
            windows: windows,
            windowID: \.windowID,
            cachedPIDs: [78: 917]
        )
        #expect(result != nil)
        #expect(result?.windowID != 78,
                "scan must run via an unresolved window, never a cached one")
    }
}
