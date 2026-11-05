//
//  MenuBarItemCacheMergeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Menu bar item cache merge")
struct MenuBarItemCacheMergeTests {
    private func item(
        namespace: MenuBarItemTag.Namespace,
        title: String,
        windowID: UInt32
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, windowID: windowID),
            windowID: windowID,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: false
        )
    }

    @Test("Fresh items come first and cached items fill the gaps")
    func mergesItems() {
        let fresh = item(namespace: .string("com.example.fresh"), title: "Fresh", windowID: 3)
        let cachedControl = item(namespace: .thaw, title: "Visible", windowID: 1)
        let cachedHidden = item(namespace: .string("com.example.hidden"), title: "Hidden", windowID: 2)

        let merged = MenuBarItemCache.merging(
            [fresh],
            withCachedItems: [cachedControl, cachedHidden]
        )

        #expect(merged == [fresh, cachedControl, cachedHidden])
    }

    @Test("A cached item with a churned window ID does not duplicate a fresh item")
    func deduplicatesPersistentIdentities() {
        let cached = item(namespace: .string("com.example.app"), title: "Menu", windowID: 2)
        let fresh = item(namespace: .string("com.example.app"), title: "Menu", windowID: 99)

        let merged = MenuBarItemCache.merging(
            [fresh],
            withCachedItems: [cached]
        )

        #expect(merged == [fresh])
    }
}
