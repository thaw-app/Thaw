//
//  DefaultsAccessorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

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
