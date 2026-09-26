//
//  SourceResolutionProbeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers ``MenuBarItemManager/windowIDsNeedingSourceResolution(cachedItems:currentWindowIDs:)``,
/// which decides whether a cycle with no window change should still ask for source processes.
///
/// Without a source, an item's namespace falls back to its window owner (Control
/// Center for hosted items) and its name to "Menu Bar Item". The first AX scan
/// after login often misses and the window never changes again, so the bad
/// reading used to last until relaunch.
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

    /// The steady state must cost nothing: every item knows its owner.
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

    /// A control item's AX children are disabled dividers, so asking is a sure miss
    /// that can trigger a full extras-menu-bar scan of every app. Its PID is known locally.
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

    /// The cache holds items through a failed reading; asking about a gone window
    /// spends an AX scan every tick on something that can never resolve.
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
