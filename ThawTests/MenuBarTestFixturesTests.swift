//
//  MenuBarTestFixturesTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Sanity tests for the synthetic fixture builders in
/// MenuBarTestFixtures.swift. These pin down that the fixtures produce values
/// with the documented defaults so the planner tests built on top of them stay
/// stable.
final class MenuBarTestFixturesTests: XCTestCase {
    func testAppItemTagBuildsExpectedNamespaceAndTitle() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")
        XCTAssertEqual(String(describing: tag.namespace), "com.example.app")
        XCTAssertEqual(tag.title, "Status")
        XCTAssertEqual(tag.instanceIndex, 0)
        XCTAssertNil(tag.windowID)
    }

    func testAppItemTagSupportsInstanceIndex() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status", instanceIndex: 2)
        XCTAssertEqual(tag.instanceIndex, 2)
    }

    func testMenuBarItemFixtureDefaultsToMovableHideableItem() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")
        let item = MenuBarItem.fixture(tag: tag, windowID: 42)

        XCTAssertEqual(item.windowID, 42)
        XCTAssertEqual(item.tag, tag)
        XCTAssertEqual(item.sourcePID, 1234)
        XCTAssertEqual(item.ownerPID, 1234)
        XCTAssertEqual(item.bounds, CGRect(x: 0, y: 0, width: 24, height: 22))
        XCTAssertTrue(item.isMovable)
        XCTAssertTrue(item.canBeHidden)
        XCTAssertFalse(item.isControlItem)
        XCTAssertTrue(item.isOnScreen)
    }

    func testMenuBarItemFixtureRespectsExplicitBounds() {
        let bounds = CGRect(x: 100, y: 0, width: 30, height: 22)
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 1,
            bounds: bounds
        )
        XCTAssertEqual(item.bounds, bounds)
    }

    func testControlItemPairFixtureWithoutAlwaysHidden() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22)
        )

        XCTAssertEqual(pair.hidden.tag, .hiddenControlItem)
        XCTAssertEqual(pair.hidden.bounds.minX, 500)
        XCTAssertNil(pair.alwaysHidden)
    }

    func testControlItemPairFixtureWithAlwaysHidden() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 24, height: 22)
        )

        XCTAssertEqual(pair.hidden.tag, .hiddenControlItem)
        XCTAssertEqual(pair.alwaysHidden?.tag, .alwaysHiddenControlItem)
        XCTAssertEqual(pair.alwaysHidden?.bounds.minX, 200)
    }

    func testControlItemPairFixtureWindowIDsAreDistinct() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        XCTAssertNotEqual(pair.hidden.windowID, pair.alwaysHidden?.windowID)
    }
}
