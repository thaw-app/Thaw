//
//  BadgeIndexTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterization tests for the New Items badge placement search.
///
/// The badge's saved position is expressed relative to an anchor. When that
/// anchor is gone, the nearest surviving sibling from the saved order stands
/// in for it: a sibling to the anchor's left places the badge after that
/// sibling, one to its right places the badge before.
final class BadgeIndexTests: XCTestCase {
    private let profileOrder = ["a", "b", "c", "d", "e"]

    /// Anchor "c" at index 2, walking left: "b" is the nearest left sibling and
    /// is present, so the badge goes after it.
    func testWalkLeftFindsNearestLeftSibling() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["a", "b", "z"],
            walkLeftFirst: true
        )
        XCTAssertEqual(index, 2, "expected placement after \"b\" at index 1")
    }

    /// Walking left skips saved siblings that are no longer present and keeps
    /// going toward index 0.
    func testWalkLeftSkipsAbsentSiblings() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["a", "z"],
            walkLeftFirst: true
        )
        XCTAssertEqual(index, 1, "expected placement after \"a\" at index 0")
    }

    /// With nothing to the left present, the search falls back to the right and
    /// places the badge before that sibling.
    func testWalkLeftFallsBackToTheRight() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["z", "d"],
            walkLeftFirst: true
        )
        XCTAssertEqual(index, 1, "expected placement before \"d\" at index 1")
    }

    /// Walking right prefers the right sibling even when a left one exists.
    func testWalkRightPrefersRightSibling() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["b", "d"],
            walkLeftFirst: false
        )
        XCTAssertEqual(index, 1, "expected placement before \"d\" at index 1")
    }

    /// Walking right falls back to the left when nothing to the right survives.
    func testWalkRightFallsBackToTheLeft() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["b", "z"],
            walkLeftFirst: false
        )
        XCTAssertEqual(index, 1, "expected placement after \"b\" at index 0")
    }

    /// An anchor at the head has no left side to search, which must not read
    /// off the start of the saved order.
    func testAnchorAtHeadSearchesOnlyRight() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 0,
            itemIdentifiers: ["c"],
            walkLeftFirst: true
        )
        XCTAssertEqual(index, 0, "expected placement before \"c\" at index 0")
    }

    /// An anchor at the tail has no right side to search, which must not read
    /// past the end of the saved order.
    func testAnchorAtTailSearchesOnlyLeft() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: profileOrder.count - 1,
            itemIdentifiers: ["c"],
            walkLeftFirst: false
        )
        XCTAssertEqual(index, 1, "expected placement after \"c\" at index 0")
    }

    /// No surviving sibling in either direction yields no placement.
    func testNoSurvivingSiblingReturnsNil() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["y", "z"],
            walkLeftFirst: true
        )
        XCTAssertNil(index)
    }

    /// A single-entry saved order leaves both sides empty.
    func testSingleEntryProfileOrderReturnsNil() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: ["a"],
            anchorPos: 0,
            itemIdentifiers: ["a"],
            walkLeftFirst: true
        )
        XCTAssertNil(index)
    }
}
