//
//  DragGeometrySourceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Darwin
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct DragGeometrySourceTests {
    private static func item(_ title: String, owner: pid_t, source: pid_t) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: UInt32(owner),
            ownerPID: owner,
            sourcePID: source,
            bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test
    func theKnownOwnersAnswerWithoutAFullRead() async {
        let moved = Self.item("Moved", owner: 10, source: 11)
        let anchor = Self.item("Anchor", owner: 20, source: 21)
        var asked = Set<pid_t>()
        var fullReads = 0
        let items = await DragGeometrySource.items(
            moving: moved,
            beside: anchor,
            fresh: { owners in
                asked = owners
                return [anchor, moved]
            },
            full: {
                fullReads += 1
                return []
            }
        )
        #expect(items.map(\.tag) == [anchor.tag, moved.tag])
        #expect(asked == [10, 11, 20, 21])
        #expect(fullReads == 0)
    }

    @Test
    func aFullReadIsTheFallbackWhenTheKnownOwnersCannotAnswer() async {
        let moved = Self.item("Moved", owner: 10, source: 11)
        let anchor = Self.item("Anchor", owner: 20, source: 21)
        let items = await DragGeometrySource.items(
            moving: moved,
            beside: anchor,
            fresh: { _ in nil },
            full: { [moved] }
        )
        #expect(items.map(\.tag) == [moved.tag])
    }
}
