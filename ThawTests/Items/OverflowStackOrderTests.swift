//
//  OverflowStackOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Items macOS folds behind its overflow arrow report frames stacked on the
/// arrow, so the Visible bar must not take their order from those frames.
struct OverflowStackOrderTests {
    private static func item(_ title: String, x: CGFloat, width: CGFloat, windowID: UInt32) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 4.5, width: width, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// Frames from a live bar: a wide item and two narrow ones piled on the
    /// arrow at x = -663.5, then the first item macOS still draws.
    private static let arrow = [CGRect(x: -663.5, y: 1, width: 17.5, height: 24)]
    private static let wide = item("wide", x: -811, width: 165, windowID: 1)
    private static let first = item("first", x: -671, width: 24, windowID: 2)
    private static let second = item("second", x: -666, width: 20, windowID: 3)
    private static let drawn = item("drawn", x: -640, width: 20, windowID: 4)

    private static func titles(_ items: [MenuBarItem]) -> [String] {
        items.map(\.tag.title)
    }

    @Test("Items stacked on the overflow arrow take their saved order")
    func stackTakesSavedOrder() {
        let saved = [Self.first, Self.second, Self.wide, Self.drawn].map(\.uniqueIdentifier)
        let ordered = MenuBarItem.orderingOverflowStack(
            [Self.wide, Self.first, Self.second, Self.drawn],
            overflowBounds: Self.arrow,
            savedOrder: saved
        )
        #expect(Self.titles(ordered) == ["first", "second", "wide", "drawn"])
    }

    @Test("Without an overflow arrow the order is untouched")
    func noArrowNoChange() {
        let items = [Self.wide, Self.first, Self.second, Self.drawn]
        let saved = [Self.first, Self.second, Self.wide, Self.drawn].map(\.uniqueIdentifier)
        #expect(Self.titles(MenuBarItem.orderingOverflowStack(items, overflowBounds: [], savedOrder: saved)) == Self.titles(items))
    }

    @Test("Stacked items the saved order lacks keep their order after the known ones")
    func unknownItemsFollowKnown() {
        let ordered = MenuBarItem.orderingOverflowStack(
            [Self.wide, Self.first, Self.second, Self.drawn],
            overflowBounds: Self.arrow,
            savedOrder: [Self.second.uniqueIdentifier]
        )
        #expect(Self.titles(ordered) == ["second", "wide", "first", "drawn"])
    }
}
