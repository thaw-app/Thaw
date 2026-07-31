//
//  MenuBarItemOrderingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers `MenuBarItem.sortByLeadingEdgeThenIdentifier(_:)`.
///
/// `Array.sort(by:)` is not stable in Swift, so a bare `minX < minX`
/// comparison is free to return tied items in a different relative order on
/// every pass. Anywhere that order becomes an order of record — a persisted
/// layout, a cache signature, a before/after comparison — the instability
/// reads to the user as a spontaneous swap. These cases pin the tie-break
/// that makes the result reproducible.
@Suite("Menu bar item leading-edge ordering")
struct MenuBarItemOrderingTests {
    private func item(
        _ title: String,
        minX: CGFloat,
        windowID: CGWindowID,
        bundleID: String = "com.example.app"
    ) -> MenuBarItem {
        .fixture(
            tag: .appItem(bundleID: bundleID, title: title),
            windowID: windowID,
            bounds: CGRect(x: minX, y: 0, width: 24, height: 22)
        )
    }

    @Test("Items sort by leading edge")
    func sortsByLeadingEdge() {
        let right = item("Right", minX: 300, windowID: 1)
        let left = item("Left", minX: 100, windowID: 2)
        let middle = item("Middle", minX: 200, windowID: 3)

        let sorted = MenuBarItem.sortByLeadingEdgeThenIdentifier([right, left, middle])

        #expect(sorted.map(\.tag.title) == ["Left", "Middle", "Right"])
    }

    @Test("Items tied on minX fall back to the unique identifier")
    func tiesBreakOnIdentifier() {
        // Two items can genuinely report the same minX mid-reflow, while an
        // owner re-lays out its own item, or when a zero-width control item
        // sits exactly on a neighbor's edge.
        let bravo = item("Bravo", minX: 100, windowID: 1)
        let alpha = item("Alpha", minX: 100, windowID: 2)

        let sorted = MenuBarItem.sortByLeadingEdgeThenIdentifier([bravo, alpha])

        #expect(sorted.map(\.tag.title) == ["Alpha", "Bravo"])
    }

    @Test("The tie-break ignores window ID, which is not launch-stable")
    func tieBreakIsIndependentOfWindowID() {
        // windowID changes between app restarts, so an order of record
        // derived from it would not survive a relaunch.
        let alphaHighID = item("Alpha", minX: 100, windowID: 9999)
        let bravoLowID = item("Bravo", minX: 100, windowID: 1)

        let sorted = MenuBarItem.sortByLeadingEdgeThenIdentifier([alphaHighID, bravoLowID])

        #expect(sorted.map(\.tag.title) == ["Alpha", "Bravo"])
    }

    @Test("The tie-break distinguishes same-titled items from different owners")
    func tieBreakUsesNamespace() {
        let zebra = item("Status", minX: 100, windowID: 1, bundleID: "com.example.zebra")
        let apple = item("Status", minX: 100, windowID: 2, bundleID: "com.example.apple")

        let sorted = MenuBarItem.sortByLeadingEdgeThenIdentifier([zebra, apple])

        #expect(sorted.map(\.uniqueIdentifier) == [apple.uniqueIdentifier, zebra.uniqueIdentifier])
    }

    @Test("The order is identical regardless of input order")
    func resultIsIndependentOfInputOrder() {
        // The property the tie-break exists for: any permutation of the same
        // items resolves to one order.
        let items = [
            item("Alpha", minX: 100, windowID: 1),
            item("Bravo", minX: 100, windowID: 2),
            item("Charlie", minX: 100, windowID: 3),
            item("Delta", minX: 200, windowID: 4),
        ]
        let expected = MenuBarItem.sortByLeadingEdgeThenIdentifier(items).map(\.uniqueIdentifier)

        #expect(expected == ["com.example.app:Alpha", "com.example.app:Bravo", "com.example.app:Charlie", "com.example.app:Delta"])

        for permutation in [items.reversed().map(\.self), items.shuffled(), items.shuffled()] {
            let sorted = MenuBarItem.sortByLeadingEdgeThenIdentifier(permutation)
            #expect(sorted.map(\.uniqueIdentifier) == expected)
        }
    }

    @Test("Sorting an empty or single-item list is a no-op")
    func degenerateInputs() {
        #expect(MenuBarItem.sortByLeadingEdgeThenIdentifier([]).isEmpty)

        let only = item("Only", minX: 42, windowID: 1)
        #expect(MenuBarItem.sortByLeadingEdgeThenIdentifier([only]).map(\.tag.title) == ["Only"])
    }
}
