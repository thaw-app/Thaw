//
//  DefaultsStoreRoutingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

/// Settings that used to go straight to UserDefaults.standard now follow
/// Defaults.store, so a test's throwaway store catches them instead of the
/// person's real settings.
@MainActor
@Suite("Defaults store routing", .scratchDefaults)
struct DefaultsStoreRoutingTests {
    private func item(_ title: String, bundle: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: title, instanceIndex: 0),
            windowID: CGWindowID(abs(title.hashValue % 10000) + 1),
            ownerPID: 999_997,
            sourcePID: 999_997,
            bounds: CGRect(x: 600, y: 0, width: 22, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("Search recents made without a store save to Defaults.store")
    func searchRecents() {
        MenuBarSearchRecents().record(item("Alpha", bundle: "com.example.routing"))
        #expect(Defaults.store.stringArray(forKey: Defaults.Key.menuBarSearchRecents.rawValue)?.count == 1)
    }

    @Test("Item groups made without a store save to Defaults.store")
    func itemGroups() throws {
        let manager = MenuBarItemGroupManager()
        _ = try #require(manager.createGroup(
            name: "Routed",
            items: [item("A", bundle: "com.example.routing.one"), item("B", bundle: "com.example.routing.two")]
        ))
        #expect(Defaults.store.object(forKey: Defaults.Key.menuBarItemGroups.rawValue) != nil)
        #expect(MenuBarItemGroupManager().groupSet == manager.groupSet)
    }

    @Test("A dismissed layout suggestion is saved to and read from Defaults.store")
    func layoutSuggestionDismissal() {
        #expect(!LayoutSuggestionDismissal.isQuiet(.itemsBehindNotch))
        LayoutSuggestionDismissal.dismiss(.itemsBehindNotch)
        #expect(Defaults.store.object(forKey: "LayoutSuggestions.dismissed.itemsBehindNotch") is Date)
        #expect(LayoutSuggestionDismissal.isQuiet(.itemsBehindNotch))
    }

    @Test("The notch panel reads its switch from Defaults.store")
    func notchPanelSwitch() {
        let controller = NotchPanelController()
        #expect(!controller.isEnabled)
        Defaults.store.set(true, forKey: Defaults.Key.enableMenuBarItemDescenders.rawValue)
        #expect(controller.isEnabled)
    }

    @Test("Simulating a notch through Defaults.store gives every screen one")
    func simulatedNotch() throws {
        let screen = try #require(NSScreen.screens.first)
        Defaults.store.set(true, forKey: Defaults.Key.debugSimulateNotch.rawValue)
        #expect(screen.hasNotch)
        #expect(screen.frameOfNotch != nil)
    }
}
