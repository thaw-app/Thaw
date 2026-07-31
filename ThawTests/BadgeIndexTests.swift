//
//  BadgeIndexTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterization tests for the New Items badge placement search.
///
/// The badge's saved position is expressed relative to an anchor. When that
/// anchor is gone, the nearest surviving sibling from the saved order stands
/// in for it: a sibling to the anchor's left places the badge after that
/// sibling, one to its right places the badge before.
@Suite("New items badge index")
struct BadgeIndexTests {
    private let profileOrder = ["a", "b", "c", "d", "e"]

    /// Anchor "c" at index 2, walking left: "b" is the nearest left sibling and
    /// is present, so the badge goes after it.
    @Test("Walking left finds the nearest surviving left sibling")
    func walkLeftFindsNearestLeftSibling() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["a", "b", "z"],
            walkLeftFirst: true
        )
        #expect(index == 2, "expected placement after \"b\" at index 1")
    }

    /// Walking left skips saved siblings that are no longer present and keeps
    /// going toward index 0.
    @Test("Walking left skips absent siblings")
    func walkLeftSkipsAbsentSiblings() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["a", "z"],
            walkLeftFirst: true
        )
        #expect(index == 1, "expected placement after \"a\" at index 0")
    }

    /// With nothing to the left present, the search falls back to the right and
    /// places the badge before that sibling.
    @Test("Walking left falls back to the right when nothing survives on the left")
    func walkLeftFallsBackToTheRight() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["z", "d"],
            walkLeftFirst: true
        )
        #expect(index == 1, "expected placement before \"d\" at index 1")
    }

    /// Walking right prefers the right sibling even when a left one exists.
    @Test("Walking right prefers the right sibling")
    func walkRightPrefersRightSibling() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["b", "d"],
            walkLeftFirst: false
        )
        #expect(index == 1, "expected placement before \"d\" at index 1")
    }

    /// Walking right falls back to the left when nothing to the right survives.
    @Test("Walking right falls back to the left when nothing survives on the right")
    func walkRightFallsBackToTheLeft() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["b", "z"],
            walkLeftFirst: false
        )
        #expect(index == 1, "expected placement after \"b\" at index 0")
    }

    /// An anchor at the head has no left side to search, which must not read
    /// off the start of the saved order.
    @Test("An anchor at the head searches only to the right")
    func anchorAtHeadSearchesOnlyRight() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 0,
            itemIdentifiers: ["c"],
            walkLeftFirst: true
        )
        #expect(index == 0, "expected placement before \"c\" at index 0")
    }

    /// An anchor at the tail has no right side to search, which must not read
    /// past the end of the saved order.
    @Test("An anchor at the tail searches only to the left")
    func anchorAtTailSearchesOnlyLeft() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: profileOrder.count - 1,
            itemIdentifiers: ["c"],
            walkLeftFirst: false
        )
        #expect(index == 1, "expected placement after \"c\" at index 0")
    }

    /// No surviving sibling in either direction yields no placement.
    @Test("No surviving sibling in either direction yields no placement")
    func noSurvivingSiblingReturnsNil() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: profileOrder,
            anchorPos: 2,
            itemIdentifiers: ["y", "z"],
            walkLeftFirst: true
        )
        #expect(index == nil)
    }

    /// A single-entry saved order leaves both sides empty.
    @Test("A single-entry saved order yields no placement")
    func singleEntryProfileOrderReturnsNil() {
        let index = MenuBarItemManager.badgeIndex(
            profileOrder: ["a"],
            anchorPos: 0,
            itemIdentifiers: ["a"],
            walkLeftFirst: true
        )
        #expect(index == nil)
    }
}
