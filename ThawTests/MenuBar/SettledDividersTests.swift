//
//  SettledDividersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Dividers for a settled normalization")
struct SettledDividersTests {
    private static func item(_ title: String, x: CGFloat, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.app\(windowID)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: pid_t(windowID),
            sourcePID: pid_t(windowID),
            bounds: CGRect(x: x, y: 3, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private let cached = [item("A", x: 1500, windowID: 1), item("B", x: 1700, windowID: 2)]
    private let hidden = item("Hidden", x: 1577, windowID: 10)
    private let alwaysHidden = item("AlwaysHidden", x: 1616, windowID: 11)

    @Test("The cache's missing dividers come back from the last walk")
    func dividersAreAdded() throws {
        let result = try #require(ControlOrderRules.withDividers(
            cached, ControlItemPair(hidden: hidden, alwaysHidden: alwaysHidden)
        ))
        #expect(result.items.map(\.windowID) == [1, 2, 10, 11])
        #expect(result.controlItems.hidden.windowID == 10)
        #expect(result.controlItems.alwaysHidden?.windowID == 11)
    }

    @Test("A divider already present is not listed twice")
    func presentDividerIsNotDuplicated() throws {
        let result = try #require(ControlOrderRules.withDividers(
            cached + [hidden], ControlItemPair(hidden: hidden, alwaysHidden: nil)
        ))
        #expect(result.items.map(\.windowID) == [1, 2, 10])
    }

    @Test("Without Always Hidden only the Hidden divider is added")
    func onlyHiddenDivider() throws {
        let result = try #require(ControlOrderRules.withDividers(cached, ControlItemPair(hidden: hidden, alwaysHidden: nil)))
        #expect(result.items.map(\.windowID) == [1, 2, 10])
        #expect(result.controlItems.alwaysHidden == nil)
    }

    @Test("A cached divider with the same window keeps the cache's copy")
    func cachedCopyWins() throws {
        let moved = Self.item("Hidden", x: 1400, windowID: 10)
        let result = try #require(ControlOrderRules.withDividers(
            cached + [moved], ControlItemPair(hidden: hidden, alwaysHidden: alwaysHidden)
        ))
        #expect(result.items.map(\.windowID) == [1, 2, 10, 11])
        #expect(result.items.first { $0.windowID == 10 }?.bounds.minX == 1400)
    }

    @Test("An empty cache still gets the dividers")
    func emptyCache() throws {
        let result = try #require(ControlOrderRules.withDividers([], ControlItemPair(hidden: hidden, alwaysHidden: alwaysHidden)))
        #expect(result.items.map(\.windowID) == [10, 11])
    }

    @Test("The out-of-order trio is detectable once the dividers are back")
    func trioDetectableWithDividers() throws {
        let visible = MenuBarItem(
            tag: .visibleControlItem, windowID: 20, ownerPID: 1, sourcePID: 1,
            bounds: CGRect(x: 1733, y: 3, width: 24, height: 24), title: "Visible", isOnScreen: true
        )
        let result = try #require(ControlOrderRules.withDividers(
            cached + [visible], ControlItemPair(hidden: hidden, alwaysHidden: alwaysHidden)
        ))
        let found = try #require(result.items.first { $0.tag.matchesVisibleControlItem })
        #expect(!ControlOrderRules.controlTrioInCanonicalOrder(
            alwaysHidden: result.controlItems.alwaysHidden, hidden: result.controlItems.hidden, visible: found
        ))
    }

    @Test("Without a known Hidden divider nothing can be ordered")
    func noDividersIsNil() {
        #expect(ControlOrderRules.withDividers(cached, nil) == nil)
    }

    @Test("With the cache's dividers dropped, the pre-reveal divider check passes")
    func preRevealCheckPassesWithoutCachedDividers() {
        let display = CGMainDisplayID()
        let bounds = CGDisplayBounds(display)
        let items = [
            Self.item("A", x: bounds.maxX - 300, windowID: 1),
            Self.item("B", x: bounds.maxX - 200, windowID: 2),
        ]
        var cache = MenuBarItemCache(displayID: display)
        cache[.visible] = items
        let manager = MenuBarItemManager()
        manager.itemCache = cache
        manager.lastKnownControlItems = nil

        let dividers = manager.cacheDividers()

        #expect(!ControlOrderRules.dividerIsOffTheBar(dividers, among: manager.managedItems, displays: [bounds]))
        #expect(dividers.hidden.bounds.minX == bounds.minX)
        #expect(manager.lastKnownControlItems == nil)
    }

    @Test("A stand-in pair is never kept as the last walk's dividers")
    func standInsAreNeverKept() throws {
        let standIns = CacheDividers.standIns(leadingX: 0, alwaysHiddenEnabled: true, ownerPID: 501)
        #expect(CacheDividers.live(standIns) == nil)
        let walked = try #require(CacheDividers.live(ControlItemPair(hidden: hidden, alwaysHidden: alwaysHidden)))
        #expect(walked.hidden.windowID == 10)
        #expect(walked.alwaysHidden?.windowID == 11)
    }

    @Test("Every cache-based pass gets the same pair for the same cache")
    func oneSourceForEveryPass() {
        let display = CGMainDisplayID()
        var cache = MenuBarItemCache(displayID: display)
        cache[.visible] = cached
        let manager = MenuBarItemManager()
        manager.itemCache = cache

        manager.lastKnownControlItems = nil
        let walkPass = manager.cacheDividers(on: display)
        let cachePass = manager.cacheDividers()
        #expect(walkPass.hidden == cachePass.hidden)
        #expect(walkPass.alwaysHidden == cachePass.alwaysHidden)
        #expect(CacheDividers.isStandIn(cachePass.hidden))

        manager.lastKnownControlItems = ControlItemPair(hidden: hidden, alwaysHidden: alwaysHidden)
        #expect(manager.cacheDividers(on: display).hidden == hidden)
        #expect(manager.cacheDividers().hidden == hidden)
        #expect(manager.cacheDividers().alwaysHidden == alwaysHidden)
    }

    @Test("Stand-ins sit at the leading edge of the pass's display, the main screen only as a fallback")
    func standInsFollowThePassDisplay() {
        let secondary = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(CacheDividers.leadingX(display: secondary, mainScreen: main) == 1920)
        #expect(CacheDividers.leadingX(display: nil, mainScreen: main) == 0)
        #expect(CacheDividers.leadingX(display: nil, mainScreen: nil) == 0)
        let standIns = CacheDividers.standIns(leadingX: 1920, alwaysHiddenEnabled: false, ownerPID: 501)
        #expect(standIns.hidden.bounds.minX == 1920)
        #expect(standIns.alwaysHidden == nil)
    }

    @Test("Stand-ins added to the cache are judged like the walked pair")
    func standInsJoinTheCachedItems() throws {
        let standIns = CacheDividers.standIns(leadingX: 0, alwaysHiddenEnabled: true, ownerPID: 501)
        let result = try #require(ControlOrderRules.withDividers(cached, standIns))
        #expect(result.items.map(\.windowID) == [1, 2, CacheDividers.standInHiddenWindowID, CacheDividers.standInAlwaysHiddenWindowID])
        #expect(!ControlOrderRules.dividerIsOffTheBar(result.controlItems, among: result.items, displays: []))
    }
}
