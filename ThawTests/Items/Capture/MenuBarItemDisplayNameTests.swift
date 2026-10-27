//
//  MenuBarItemDisplayNameTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Display names are memoized, but a custom name always wins", .scratchDefaults)
struct MenuBarItemDisplayNameTests {
    private func makeItem(
        _ title: String,
        namespace: MenuBarItemTag.Namespace = .string("com.example.names"),
        pid: pid_t = 999_994
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title, instanceIndex: 0),
            windowID: 31,
            ownerPID: pid,
            sourcePID: pid,
            bounds: CGRect(x: 700, y: 0, width: 22, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("A custom name is read fresh each time, past the cached name")
    func customNameBypassesCache() {
        MenuBarItemDisplayName.clear()
        defer { MenuBarItemDisplayName.clear() }
        var item = makeItem("Battery")
        let automatic = MenuBarItemDisplayName.displayName(for: item)
        #expect(automatic == item.displayName)

        item.customName = "Power"
        #expect(MenuBarItemDisplayName.displayName(for: item) == "Power")

        item.customName = "   "
        #expect(item.customName == nil)
        #expect(MenuBarItemDisplayName.displayName(for: item) == automatic)
    }

    @Test("A spacer shows as Spacer")
    func spacerName() {
        MenuBarItemDisplayName.clear()
        defer { MenuBarItemDisplayName.clear() }
        let item = makeItem(MenuBarSpacerManager.autosavePrefix + UUID().uuidString, namespace: .thaw)
        #expect(MenuBarItemDisplayName.displayName(for: item) == String(localized: "Spacer"))
        #expect(!item.isUserActionable)
    }

    @Test("An owner that no running process matches has no name and no subtitle")
    func unresolvableOwner() {
        MenuBarItemDisplayName.clear()
        defer { MenuBarItemDisplayName.clear() }
        let item = makeItem("Ghost", pid: 999_995)
        #expect(MenuBarItemDisplayName.ownerName(for: item) == nil)
        #expect(MenuBarItemDisplayName.subtitle(for: item) == nil)
    }

    @Test("The test host's own process resolves to its name, then from the cache")
    func resolvableOwner() throws {
        MenuBarItemDisplayName.clear()
        defer { MenuBarItemDisplayName.clear() }
        let pid = ProcessInfo.processInfo.processIdentifier
        let expected = try #require(NSRunningApplication(processIdentifier: pid)?.localizedName)
        var item = makeItem("Status", pid: pid)

        #expect(MenuBarItemDisplayName.ownerName(for: item) == expected)
        #expect(MenuBarItemDisplayName.ownerName(for: item) == expected)

        item.customName = "Different"
        #expect(MenuBarItemDisplayName.subtitle(for: item) == expected)

        item.customName = expected
        #expect(MenuBarItemDisplayName.subtitle(for: item) == nil)
    }

    @Test("The name cache refills after it reaches its cap")
    func cacheCap() {
        MenuBarItemDisplayName.clear()
        defer { MenuBarItemDisplayName.clear() }
        for index in 0 ..< 300 {
            let item = makeItem("Item \(index)")
            #expect(MenuBarItemDisplayName.displayName(for: item) == item.displayName)
        }
    }

    @Test("Ordinary items are actionable and control items, folders and clones are not")
    func userActionable() {
        #expect(makeItem("Plain").isUserActionable)
        #expect(!makeItem(GroupFolders.autosavePrefix + UUID().uuidString, namespace: .thaw).isUserActionable)
        #expect(!makeItem(ControlItemIdentifier.hidden.rawValue, namespace: .thaw).isUserActionable)
    }
}
