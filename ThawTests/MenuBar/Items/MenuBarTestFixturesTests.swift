//
//  MenuBarTestFixturesTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Sanity tests for the synthetic fixture builders in
/// MenuBarTestFixtures.swift. These pin down that the fixtures produce values
/// with the documented defaults so the planner tests built on top of them stay
/// stable.
@Suite("Menu bar test fixtures")
struct MenuBarTestFixturesTests {
    @Test("An app item tag carries its bundle identifier and title")
    func appItemTagBuildsExpectedNamespaceAndTitle() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")
        #expect(String(describing: tag.namespace) == "com.example.app")
        #expect(tag.title == "Status")
        #expect(tag.instanceIndex == 0)
        #expect(tag.windowID == nil)
    }

    @Test("An app item tag keeps an explicit instance index")
    func appItemTagSupportsInstanceIndex() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status", instanceIndex: 2)
        #expect(tag.instanceIndex == 2)
    }

    @Test("A menu bar item fixture defaults to a movable, hideable, on-screen item")
    func menuBarItemFixtureDefaultsToMovableHideableItem() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")
        let item = MenuBarItem.fixture(tag: tag, windowID: 42)

        #expect(item.windowID == 42)
        #expect(item.tag == tag)
        #expect(item.sourcePID == 1234)
        #expect(item.ownerPID == 1234)
        #expect(item.bounds == CGRect(x: 0, y: 0, width: 24, height: 22))
        #expect(item.isMovable)
        #expect(item.canBeHidden)
        #expect(!item.isControlItem)
        #expect(item.isOnScreen)
    }

    @Test("A menu bar item fixture keeps explicitly supplied bounds")
    func menuBarItemFixtureRespectsExplicitBounds() {
        let bounds = CGRect(x: 100, y: 0, width: 30, height: 22)
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 1,
            bounds: bounds
        )
        #expect(item.bounds == bounds)
    }

    @Test("A control item pair without an always-hidden control has only the hidden one")
    func controlItemPairFixtureWithoutAlwaysHidden() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22)
        )

        #expect(pair.hidden.tag == .hiddenControlItem)
        #expect(pair.hidden.bounds.minX == 500)
        #expect(pair.alwaysHidden == nil)
    }

    @Test("A control item pair with an always-hidden control tags and places both")
    func controlItemPairFixtureWithAlwaysHidden() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 24, height: 22)
        )

        #expect(pair.hidden.tag == .hiddenControlItem)
        #expect(pair.alwaysHidden?.tag == .alwaysHiddenControlItem)
        #expect(pair.alwaysHidden?.bounds.minX == 200)
    }

    @Test("A control item pair gives its two items distinct window identifiers")
    func controlItemPairFixtureWindowIDsAreDistinct() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        #expect(pair.hidden.windowID != pair.alwaysHidden?.windowID)
    }
}
