//
//  LayoutBarGroupOrderPersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
@testable import Thaw
import XCTest

/// `layoutItemsForPersistence` turns the layout bar's visual arrangement into
/// the order Thaw persists.
///
/// A collapsed group is one arranged view standing in for several items, so if
/// this function matched only `.item` those members would be dropped from the
/// saved section order while remaining in the menu bar — items silently
/// vanishing from a saved layout. This is the sharpest failure mode in the
/// collapse work, which is why it is pinned before anything renders a pill.
@MainActor
final class LayoutBarGroupOrderPersistenceTests: XCTestCase {
    private func item(_ bundle: String, _ title: String, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: bundle, title: title),
            windowID: windowID,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 22)
        )
    }

    func testCollapsedGroupExpandsIntoItsMembers() {
        let a = item("com.a", "One", windowID: 1)
        let g1 = item("com.g", "G1", windowID: 2)
        let g2 = item("com.g", "G2", windowID: 3)
        let b = item("com.b", "Two", windowID: 4)

        let result = LayoutBarPaddingView.persistableItems(from: [
            .item(a),
            .collapsedGroup(members: [g1, g2]),
            .item(b),
        ])

        XCTAssertEqual(
            result.map(\.uniqueIdentifier),
            [a, g1, g2, b].map(\.uniqueIdentifier),
            "a collapsed group must contribute every member, in order"
        )
    }

    func testMixedArrangementYieldsExactlyTheRealItems() {
        let a = item("com.a", "One", windowID: 1)
        let g1 = item("com.g", "G1", windowID: 2)
        let g2 = item("com.g", "G2", windowID: 3)

        let result = LayoutBarPaddingView.persistableItems(from: [
            .item(a),
            .newItemsBadge,
            .collapsedGroup(members: [g1, g2]),
        ])

        XCTAssertEqual(result.map(\.uniqueIdentifier), [a, g1, g2].map(\.uniqueIdentifier))
    }

    /// Control items are structural. The existing rule keeps only the movable
    /// visible Thaw icon; a collapsed group must not smuggle a divider through.
    func testControlItemsInsideACollapsedGroupAreStillFiltered() {
        let g1 = item("com.g", "G1", windowID: 2)
        let control = MenuBarItem.fixture(tag: .hiddenControlItem, windowID: 9)

        let result = LayoutBarPaddingView.persistableItems(from: [
            .collapsedGroup(members: [g1, control]),
        ])

        XCTAssertEqual(result.map(\.uniqueIdentifier), [g1.uniqueIdentifier])
    }

    func testExpandedGroupsAreUnaffected() {
        let g1 = item("com.g", "G1", windowID: 2)
        let g2 = item("com.g", "G2", windowID: 3)

        let result = LayoutBarPaddingView.persistableItems(from: [
            .item(g1),
            .item(g2),
        ])

        XCTAssertEqual(result.map(\.uniqueIdentifier), [g1, g2].map(\.uniqueIdentifier))
    }

    func testEmptyArrangementYieldsNothing() {
        XCTAssertTrue(LayoutBarPaddingView.persistableItems(from: []).isEmpty)
    }
}
