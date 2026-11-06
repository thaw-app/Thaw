//
//  UserSwitchedOffAppsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Apps switched off in System Settings stay out of the Thaw Bar")
struct UserSwitchedOffAppsTests {
    private func item(_ bundleID: String, title: String = "Item-0") -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: title, instanceIndex: 0),
            windowID: 1,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: -1, y: 1068, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("An app switched off in System Settings is left out, and every other item stays in order")
    func switchedOffAppIsLeftOut() {
        let items = [item("org.telegram.desktop"), item("com.example.kept"), item("com.qspace.pro"), item("com.example.other")]

        let shown = UserSwitchedOffApps.excluding(items, switchedOff: ["org.telegram.desktop", "com.qspace.pro"])

        #expect(shown.map(\.tag.namespace.description) == ["com.example.kept", "com.example.other"])
    }

    @Test("With nothing switched off every item stays")
    func nothingSwitchedOffKeepsAll() {
        let items = [item("com.example.a"), item("com.example.b")]

        #expect(UserSwitchedOffApps.excluding(items, switchedOff: []) == items)
    }

    @Test("Thaw's own items are never counted as switched off by the user")
    func thawsOwnItemsAreNotTheUsers() {
        let switchedOff = UserSwitchedOffApps.bundleIDs(
            switchedOff: ["org.telegram.desktop", "com.stonerl.Thaw.extra.timemachine"],
            ownedByThaw: { $0.hasPrefix("com.stonerl.Thaw") }
        )

        #expect(switchedOff == ["org.telegram.desktop"])
    }

    @Test("Only items named by an app's bundle are asked about")
    func bundleIDsOfItems() {
        let titled = MenuBarItem(
            tag: MenuBarItemTag(namespace: .null, title: "Item-0", instanceIndex: 0),
            windowID: 2, ownerPID: 2, sourcePID: 2, bounds: .zero, title: "Item-0", isOnScreen: true
        )

        #expect(UserSwitchedOffApps.bundleIDs(of: [item("com.example.a"), item("com.example.a", title: "Second"), titled]) == ["com.example.a"])
    }
}
