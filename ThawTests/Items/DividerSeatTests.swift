//
//  DividerSeatTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A divider whose frame stopped following the bar is seated by its weight")
struct DividerSeatTests {
    private func item(_ name: String, x: CGFloat, width: CGFloat, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(name)"), title: name, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 3, width: width, height: 24),
            title: name,
            isOnScreen: true
        )
    }

    private func divider(x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: .hiddenControlItem,
            windowID: 9,
            ownerPID: 100,
            sourcePID: 100,
            bounds: CGRect(x: x, y: 3, width: 2, height: 24),
            title: "Thaw.ControlItem.Hidden",
            isOnScreen: true
        )
    }

    /// The bar around the Hidden divider from the log that showed this, weights falling left to right.
    private var bar: [(MenuBarItem, Int)] {
        [
            (item("Far", x: 1303, width: 24, windowID: 1), 349),
            (item("Near", x: 1333, width: 34, windowID: 2), 279),
            (item("Home", x: 1390, width: 26, windowID: 3), 266),
            (item("Sound", x: 1432, width: 22, windowID: 4), 256),
            (item("After", x: 1469, width: 24, windowID: 5), 190),
            (item("Bluetooth", x: 1508, width: 16, windowID: 6), 174),
        ]
    }

    private func weights(_ bar: [(MenuBarItem, Int)], divider: Int) -> (MenuBarItem) -> Int? {
        { item in item.isControlItem ? divider : bar.first { $0.0.windowID == item.windowID }?.1 }
    }

    @Test("A divider reporting a seat inside another item is put between the items its weight names")
    func frozenDividerInsideAnItem() throws {
        let frame = try #require(DividerSeat.corrected(
            divider: divider(x: 1437.5), among: bar.map(\.0), weight: weights(bar, divider: 276)
        ))
        // Between the left neighbour, which ends at 1367, and Home, which starts at 1390.
        #expect(frame.minX > 1367)
        #expect(frame.maxX < 1390)
    }

    @Test("A divider frozen in an ordinary gap is still moved to the wider gap its weight names")
    func frozenDividerInAGap() throws {
        let frame = try #require(DividerSeat.corrected(
            divider: divider(x: 1460), among: bar.map(\.0), weight: weights(bar, divider: 276)
        ))
        #expect(frame.minX > 1367)
        #expect(frame.maxX < 1390)
    }

    @Test("A divider whose neighbours agree with its weight is left alone")
    func consistentDividerIsKept() {
        #expect(DividerSeat.corrected(
            divider: divider(x: 1377), among: bar.map(\.0), weight: weights(bar, divider: 276)
        ) == nil)
    }

    @Test("An item the host seated on the wrong side keeps the divider where it is")
    func strandedItemIsNotExplainedAway() {
        // Home's weight says Visible, but it sits left of a divider that holds the wide gap itself.
        let stranded: [(MenuBarItem, Int)] = [
            (item("Far", x: 1303, width: 24, windowID: 1), 349),
            (item("Near", x: 1333, width: 34, windowID: 2), 279),
            (item("Home", x: 1382, width: 26, windowID: 3), 266),
            (item("Sound", x: 1431, width: 22, windowID: 4), 256),
            (item("After", x: 1468, width: 24, windowID: 5), 190),
        ]
        #expect(DividerSeat.corrected(
            divider: divider(x: 1418), among: stranded.map(\.0), weight: weights(stranded, divider: 276)
        ) == nil)
    }

    @Test("Without a weight for the divider nothing is moved")
    func unknownWeightChangesNothing() {
        #expect(DividerSeat.corrected(divider: divider(x: 1437.5), among: bar.map(\.0), weight: { _ in nil }) == nil)
    }

    @Test("The settled pair and items carry the moved divider, and nothing else changes")
    func settledReplacesOnlyTheDivider() {
        let stale = divider(x: 1437.5)
        let items = bar.map(\.0) + [stale]
        let settled = DividerSeat.settled(
            items: items, pair: ControlItemPair(hidden: stale, alwaysHidden: nil), weight: weights(bar, divider: 276)
        )

        #expect(settled.moved)
        #expect(settled.pair.hidden.bounds.maxX < 1390)
        #expect(settled.items.count == items.count)
        #expect(settled.items.first { $0.isControlItem }?.bounds == settled.pair.hidden.bounds)
        #expect(settled.items.filter { !$0.isControlItem } == bar.map(\.0))
    }
}
