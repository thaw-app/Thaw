//
//  DefaultsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
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

    @Test("A dismissal quiets only its own suggestion, and only for the quiet interval")
    func layoutSuggestionDismissalExpires() {
        LayoutSuggestionDismissal.dismiss(.littleSnitchScriptingAccess)
        let later = Date.now.addingTimeInterval(LayoutSuggestionDismissal.quietInterval + 60)
        #expect(LayoutSuggestionDismissal.isQuiet(.littleSnitchScriptingAccess))
        #expect(!LayoutSuggestionDismissal.isQuiet(.itemsBehindNotch))
        #expect(!LayoutSuggestionDismissal.isQuiet(.littleSnitchScriptingAccess, now: later))
    }

    @Test("The notch panel reads its switch from Defaults.store")
    func notchPanelSwitch() {
        let controller = NotchPanelController()
        #expect(!controller.isEnabled)
        Defaults.store.set(true, forKey: Defaults.Key.enableMenuBarItemDescenders.rawValue)
        #expect(controller.isEnabled)
    }

    @Test("Each scratch test keeps profiles in its own temporary folder")
    func scratchProfilesFolder() throws {
        let folder = try #require(ProfileManager.directoryOverride)
        #expect(folder.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    @Test("A profile manager on the scratch folder keeps no launch record")
    func scratchProfilesHaveNoLaunchRecord() {
        #expect(AppState().profileManager.launchGate.record == nil)
    }

    @Test("Simulating a notch through Defaults.store gives every screen one")
    func simulatedNotch() throws {
        let screen = try #require(NSScreen.screens.first)
        Defaults.store.set(true, forKey: Defaults.Key.debugSimulateNotch.rawValue)
        #expect(screen.hasNotch)
        #expect(screen.frameOfNotch != nil)
    }
}

/// The typed accessors no setting model reads yet, against a scratch store.
@MainActor
@Suite("Defaults accessors", .scratchDefaults)
struct DefaultsAccessorTests {
    @Test("An array is read back from the store under its key")
    func arrayRoundTrip() {
        #expect(Defaults.array(forKey: .settingsURIWhitelist) == nil)
        Defaults.set(["com.example.one", "com.example.two"], forKey: .settingsURIWhitelist)
        #expect(Defaults.array(forKey: .settingsURIWhitelist) as? [String] == ["com.example.one", "com.example.two"])
        #expect(Defaults.store.array(forKey: Defaults.Key.settingsURIWhitelist.rawValue) as? [String] == ["com.example.one", "com.example.two"])
    }

    @Test("A URL is read back from the store under its key")
    func urlRoundTrip() {
        let url = URL(fileURLWithPath: "/nonexistent/thaw-test.plist")
        #expect(Defaults.url(forKey: .settingsURIWhitelist) == nil)
        // UserDefaults stores a URL only through its own URL setter, not the Any setter Defaults forwards to.
        Defaults.store.set(url, forKey: Defaults.Key.settingsURIWhitelist.rawValue)
        #expect(Defaults.url(forKey: .settingsURIWhitelist) == url)
    }

    @Test("The global domain is the user's own, not the app's settings")
    func globalDomainIsTheUsersGlobalDomain() {
        Defaults.set(true, forKey: .settingsURIWhitelist)
        let global = Defaults.globalDomain
        #expect(global[Defaults.Key.settingsURIWhitelist.rawValue] == nil)
        let expected = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        #expect(Set(global.keys) == Set(expected.keys))
    }
}

@MainActor
@Suite("Defaults JSON values", .scratchDefaults)
struct DefaultsCodableTests {
    @Test("An encoded value reads back, and a missing one reads as nil")
    func roundTrip() throws {
        #expect(try Defaults.decoded([String: Int].self, forKey: .knownDisplays) == nil)
        try Defaults.setEncoded(["a": 1], forKey: .knownDisplays)
        #expect(try Defaults.decoded([String: Int].self, forKey: .knownDisplays) == ["a": 1])
    }

    @Test("Stored data that doesn't decode throws, and a value that doesn't encode keeps the stored one")
    func failures() throws {
        try Defaults.setEncoded(["a": 1], forKey: .knownDisplays)
        #expect(throws: EncodingError.self) { try Defaults.setEncoded(["a": Double.nan], forKey: .knownDisplays) }
        #expect(throws: DecodingError.self) { try Defaults.decoded([String: String].self, forKey: .knownDisplays) }
        #expect(try Defaults.decoded([String: Int].self, forKey: .knownDisplays) == ["a": 1])
    }
}
