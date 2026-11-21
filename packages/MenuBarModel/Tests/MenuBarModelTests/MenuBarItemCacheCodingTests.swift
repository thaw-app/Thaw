//
//  MenuBarItemCacheCodingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Menu bar item cache coding")
struct MenuBarItemCacheCodingTests {
    private func item(_ title: String, windowID: UInt32, sourcePID: pid_t?) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.app"), title: title, windowID: windowID),
            windowID: windowID,
            ownerPID: 7,
            sourcePID: sourcePID,
            bounds: CGRect(x: 100.5, y: 0, width: 24, height: 22),
            title: title,
            isOnScreen: sourcePID != nil
        )
    }

    @Test("A cache survives being encoded and decoded, with its sections, their order and its display")
    func roundTrip() throws {
        var cache = MenuBarItemCache(displayID: 42)
        cache[.visible] = [item("Second", windowID: 2, sourcePID: 9), item("First", windowID: 1, sourcePID: nil)]
        cache[.alwaysHidden] = [item("Parked", windowID: 3, sourcePID: 11)]

        let decoded = try JSONDecoder().decode(MenuBarItemCache.self, from: JSONEncoder().encode(cache))

        #expect(decoded == cache)
        #expect(decoded.displayID == 42)
        #expect(decoded[.visible].map(\.title) == ["Second", "First"])
        #expect(decoded[.visible].first?.bounds == CGRect(x: 100.5, y: 0, width: 24, height: 22))
        #expect(decoded[.visible].map(\.sourcePID) == [9, nil])
        #expect(decoded[.hidden].isEmpty)
        #expect(decoded.item(withWindowID: 3)?.tag == cache[.alwaysHidden].first?.tag)
    }

    @Test("An empty cache with no display decodes to the same")
    func emptyRoundTrip() throws {
        let cache = MenuBarItemCache(displayID: nil)
        let decoded = try JSONDecoder().decode(MenuBarItemCache.self, from: JSONEncoder().encode(cache))
        #expect(decoded == cache)
        #expect(decoded.isEmpty)
        #expect(decoded.displayID == nil)
    }
}
