//
//  OrderConfirmationCoverageTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// A pending visible edit is retired only from a read that has the items it orders.
@Suite("Order confirmation coverage")
struct OrderConfirmationCoverageTests {
    private static func item(_ bundleID: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: "Item-0", windowID: 1),
            windowID: 1,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: "Item-0",
            isOnScreen: true
        )
    }

    private static let a = item("com.example.a")
    private static let b = item("com.example.b")
    private static let order = [a.uniqueIdentifier, b.uniqueIdentifier]

    @Test("A read that missed one of the ordered items the cache has can't confirm the order")
    func shortReadIsMissing() {
        let missed = MenuBarItemManager.desiredItemsMissing(from: [Self.a], desiredOrder: Self.order, cached: [Self.a, Self.b])
        #expect(missed == [Self.b.uniqueIdentifier])
    }

    @Test("A read with every ordered item is complete")
    func fullReadIsComplete() {
        #expect(MenuBarItemManager.desiredItemsMissing(from: [Self.b, Self.a], desiredOrder: Self.order, cached: [Self.a, Self.b]).isEmpty)
    }

    @Test("An ordered item the cache doesn't have either, such as a closed app's, isn't expected")
    func closedAppIsNotExpected() {
        #expect(MenuBarItemManager.desiredItemsMissing(from: [Self.a], desiredOrder: Self.order, cached: [Self.a]).isEmpty)
    }
}
