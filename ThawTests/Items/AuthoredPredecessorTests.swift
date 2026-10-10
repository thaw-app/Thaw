//
//  AuthoredPredecessorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// MenuBarItemManager.authoredPredecessor(of:in:excluding:) picks the
/// item a section arrival is seated behind. A multi-item drop seats its
/// members one at a time, so a member must be allowed to anchor on the
/// member seated just before it, or the group lands in reverse.
@Suite("Authored predecessor for seating")
@MainActor
struct AuthoredPredecessorTests {
    private let x = Self.item("X", x: 0)
    private let a = Self.item("A", x: 30)
    private let b = Self.item("B", x: 60)

    private var order: [MenuBarItem] {
        [x, a, b]
    }

    @Test("A member seated earlier in the same drop anchors the next one")
    func seatedMemberAnchorsTheNext() {
        let unseated = Set([b.uniqueIdentifier])
        let predecessor = MenuBarItemManager.authoredPredecessor(of: b, in: order, excluding: unseated)
        #expect(predecessor?.uniqueIdentifier == a.uniqueIdentifier)
    }

    @Test("With nothing seated yet the first member anchors on the resident item")
    func firstMemberAnchorsOnResident() {
        let moving = Set([a, b].map(\.uniqueIdentifier))
        let predecessor = MenuBarItemManager.authoredPredecessor(of: a, in: order, excluding: moving)
        #expect(predecessor?.uniqueIdentifier == x.uniqueIdentifier)
    }

    @Test("The first item in the order has no predecessor")
    func firstItemHasNoPredecessor() {
        let predecessor = MenuBarItemManager.authoredPredecessor(of: x, in: order, excluding: [])
        #expect(predecessor == nil)
    }

    @Test("An item the order does not list has no predecessor")
    func unlistedItemHasNoPredecessor() {
        let outsider = Self.item("Outsider", x: 500)
        let predecessor = MenuBarItemManager.authoredPredecessor(of: outsider, in: order, excluding: [])
        #expect(predecessor == nil)
    }

    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }
}
