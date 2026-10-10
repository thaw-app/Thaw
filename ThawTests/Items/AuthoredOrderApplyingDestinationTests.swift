//
//  AuthoredOrderApplyingDestinationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// MenuBarItemManager.authoredOrder(_:applying:to:) turns a section's
/// authored record into the order a cursor-free respace realizes. A
/// layout-pane drop commits its new order only after the move succeeds, so
/// the record the move reads still holds the pre-drag order; without this
/// helper the write re-encodes that order and nothing visibly changes.
@Suite("Authored order with a move applied")
struct AuthoredOrderApplyingDestinationTests {
    private let a = Self.item("A", x: 0)
    private let b = Self.item("B", x: 30)
    private let c = Self.item("C", x: 60)
    private let d = Self.item("D", x: 90)

    private var authored: [String] {
        [a, b, c, d].map(\.uniqueIdentifier)
    }

    @Test("Left of a target puts the item immediately before it")
    func leftOfTarget() {
        let order = MenuBarItemManager.authoredOrder(authored, applying: .leftOfItem(b), to: d)
        #expect(order == [a, d, b, c].map(\.uniqueIdentifier))
    }

    @Test("Right of a target puts the item immediately after it")
    func rightOfTarget() {
        let order = MenuBarItemManager.authoredOrder(authored, applying: .rightOfItem(c), to: a)
        #expect(order == [b, c, a, d].map(\.uniqueIdentifier))
    }

    @Test("A move the record already reflects leaves it unchanged")
    func alreadySatisfied() {
        let order = MenuBarItemManager.authoredOrder(authored, applying: .rightOfItem(a), to: b)
        #expect(order == authored)
    }

    @Test("An item the record does not list yet is inserted at its destination")
    func arrivingItemIsInserted() {
        let record = [a, b, c].map(\.uniqueIdentifier)
        let order = MenuBarItemManager.authoredOrder(record, applying: .leftOfItem(c), to: d)
        #expect(order == [a, b, d, c].map(\.uniqueIdentifier))
    }

    @Test("A target outside the record leaves it untouched")
    func foreignTargetIsIgnored() {
        let outsider = Self.item("Outsider", x: 500)
        let order = MenuBarItemManager.authoredOrder(authored, applying: .leftOfItem(outsider), to: a)
        #expect(order == authored)
    }

    @Test("Targeting the item itself is a no-op")
    func selfTargetIsIgnored() {
        let order = MenuBarItemManager.authoredOrder(authored, applying: .rightOfItem(b), to: b)
        #expect(order == authored)
    }

    @Test("Thaw's own control items are never laddered into a section")
    func controlItemsAreNeverApplied() {
        let control = MenuBarItem(
            tag: ControlItemIdentifier.visible.tag,
            windowID: 999,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: 120, y: 0, width: 24, height: 24),
            title: ControlItemIdentifier.visible.rawValue,
            isOnScreen: true
        )
        #expect(MenuBarItemManager.authoredOrder(authored, applying: .leftOfItem(a), to: control) == authored)
        #expect(MenuBarItemManager.authoredOrder(authored, applying: .leftOfItem(control), to: d) == authored)
    }

    @Test("The record never gains a duplicate")
    func noDuplicates() {
        let order = MenuBarItemManager.authoredOrder(authored, applying: .leftOfItem(a), to: c)
        #expect(order.count == authored.count)
        #expect(Set(order).count == order.count)
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
