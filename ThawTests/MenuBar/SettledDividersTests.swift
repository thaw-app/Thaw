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
}
