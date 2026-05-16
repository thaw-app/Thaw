//
//  SelectWindowForBatchScanTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterization tests for LayoutSolver.selectWindowForBatchScan,
/// the helper that pidsBody uses to pick which window to hand to
/// pidBody for the AX scan. pidBody returns immediately on a cache
/// hit at its entry, so passing an already-cached window skips the
/// scan body (and the marker-pair fallback) entirely. Picking an
/// unresolved window forces the scan to execute and resolves every
/// other unresolved window in the same batch by populating the cache
/// during the AX traversal.
///
/// Regressions where the selection reverts to `windows.first` (or any
/// other variant that can return a cached window) are caught by these
/// tests.
final class SelectWindowForBatchScanTests: XCTestCase {
    /// Simple struct mirroring the WindowInfo fields the helper
    /// actually depends on. Using a plain test type instead of
    /// WindowInfo keeps the test focused on the selection algorithm.
    private struct FakeWindow: Equatable {
        let windowID: CGWindowID
    }

    /// Empty input returns nil: no window to scan.
    func testEmptyBatchReturnsNil() {
        let result = LayoutSolver.selectWindowForBatchScan(
            windows: [FakeWindow](),
            windowID: \.windowID,
            cachedPIDs: [:]
        )
        XCTAssertNil(result)
    }

    /// Every window cached: returns nil so pidsBody skips the scan.
    /// This is the steady-state cycle after every menu bar item has
    /// resolved.
    func testAllCachedReturnsNil() {
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
        XCTAssertNil(result)
    }

    /// First window unresolved: returned. Trivial case, but also the
    /// session-start scenario where the cache is empty.
    func testFirstUnresolvedReturnsFirst() {
        let windows = [
            FakeWindow(windowID: 100),
            FakeWindow(windowID: 200),
        ]
        let result = LayoutSolver.selectWindowForBatchScan(
            windows: windows,
            windowID: \.windowID,
            cachedPIDs: [:]
        )
        XCTAssertEqual(result, windows[0])
    }

    /// First cached, second unresolved: the second is returned. This
    /// is the exact mid-session scenario the bug fix addresses: an
    /// older resolved window leads the batch but a new app's freshly-
    /// registered windowID later in the batch needs the scan.
    func testFirstCachedSecondUnresolvedReturnsSecond() {
        let windows = [
            FakeWindow(windowID: 100), // cached
            FakeWindow(windowID: 200), // unresolved (new app)
        ]
        let result = LayoutSolver.selectWindowForBatchScan(
            windows: windows,
            windowID: \.windowID,
            cachedPIDs: [100: 11]
        )
        XCTAssertEqual(result, windows[1])
    }

    /// All cached except the last: returns the last. Mirrors a batch
    /// where the only nil-PID widget is the one that just appeared
    /// at a high-indexed position.
    func testOnlyLastUnresolvedReturnsLast() {
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
        XCTAssertEqual(result, windows[2])
    }

    /// Multiple unresolved: returns the first unresolved (left-to-
    /// right). The order is the iteration order, not the order in
    /// the cache. Important for predictability when several new
    /// widgets register in the same cycle.
    func testMultipleUnresolvedReturnsFirstUnresolved() {
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
        XCTAssertEqual(result, windows[1])
    }

    /// Realistic mid-session shape observed in the field: the first
    /// window is an old resolved item, and one or more later windows
    /// (a chronic nil-PID widget plus newly-launched apps) are
    /// unresolved. The selector must skip the cached head and return
    /// one of the unresolved windows so the scan fires.
    func testRealisticBatchSkipsCachedHead() {
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
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result?.windowID, 78,
                          "scan must run via an unresolved window, never a cached one")
    }
}
