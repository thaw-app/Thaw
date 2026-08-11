//
//  SourceResolutionProbeTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers ``MenuBarItemManager/windowIDsNeedingSourceResolution(cachedItems:currentWindowIDs:)``,
/// which decides whether a cache cycle that saw no window change still has a
/// reason to ask the service for source processes.
///
/// An item cached without one has a provisional identity: its namespace falls
/// back to the owner of its window — Control Center, for everything it hosts —
/// and its name to "Menu Bar Item". The first AX scan after login routinely
/// misses, and the item's window then never changes again, so before this the
/// bad reading survived until the next launch.
@Suite("Source resolution probe")
struct SourceResolutionProbeTests {
    private func probe(
        _ cachedItems: [MenuBarItem],
        current: [CGWindowID]
    ) -> [CGWindowID] {
        MenuBarItemManager.windowIDsNeedingSourceResolution(
            cachedItems: cachedItems,
            currentWindowIDs: current
        )
    }

    private func item(windowID: CGWindowID, sourcePID: pid_t?) -> MenuBarItem {
        .fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Item-\(windowID)"),
            windowID: windowID,
            sourcePID: sourcePID
        )
    }

    /// The steady state, and the one that has to cost nothing: every item knows
    /// its owner, so there is no question to ask and no reason to recache.
    @Test("A fully resolved cache asks nothing")
    func resolvedCacheAsksNothing() {
        let items = [item(windowID: 1, sourcePID: 100), item(windowID: 2, sourcePID: 200)]
        #expect(probe(items, current: [1, 2]).isEmpty)
    }

    @Test("An item cached without a source process is asked about")
    func unresolvedItemIsAsked() {
        let items = [item(windowID: 1, sourcePID: 100), item(windowID: 2, sourcePID: nil)]
        #expect(probe(items, current: [1, 2]) == [2])
    }

    @Test("An empty cache asks nothing")
    func emptyCacheAsksNothing() {
        #expect(probe([], current: [1, 2]).isEmpty)
    }

    /// Control items are the one thing that must never be sent: their AX
    /// children are disabled dividers, so the request is a guaranteed miss that
    /// can start a full scan of every running app's extras menu bar — the
    /// expense this whole probe is shaped around avoiding. Their PID is known
    /// locally and filled in by the recache regardless.
    @Test("A control item is never asked about")
    func controlItemIsNeverAsked() {
        let control = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 3,
            sourcePID: nil
        )
        #expect(probe([control], current: [3]).isEmpty)
    }

    @Test("A control item does not suppress a real item beside it")
    func controlItemDoesNotSuppressOthers() {
        let control = MenuBarItem.fixture(tag: .hiddenControlItem, windowID: 3, sourcePID: nil)
        let unresolved = item(windowID: 4, sourcePID: nil)
        #expect(probe([control, unresolved], current: [3, 4]) == [4])
    }

    /// The cache can outlive a window — an item is held through a failed
    /// reading rather than dropped. Asking about a window that is gone spends
    /// an AX scan on something that can never resolve, every tick, forever.
    @Test("An item whose window is gone is not asked about")
    func departedWindowIsNotAsked() {
        let items = [item(windowID: 1, sourcePID: nil), item(windowID: 2, sourcePID: nil)]
        #expect(probe(items, current: [2]) == [2])
    }

    /// macOS can briefly report one item under two cache entries around a move.
    @Test("A window is asked about once")
    func duplicateWindowIsAskedOnce() {
        let items = [item(windowID: 1, sourcePID: nil), item(windowID: 1, sourcePID: nil)]
        #expect(probe(items, current: [1]) == [1])
    }
}
