//
//  HotkeyBindingStoreTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw
import ThawUI

// Writing defaults posts a change notification the app observes on the main actor.
@MainActor
@Suite("Saved shortcuts")
struct HotkeyBindingStoreTests {
    private static let combination = KeyCombination(key: KeyCode(rawValue: 0x6A), modifiers: [.command, .option])

    private func makeStore(_ name: String = #function) throws -> (HotkeyBindingStore, UserDefaults) {
        let suite = "HotkeyBindingStoreTests.\(name)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (HotkeyBindingStore(key: .menuBarItemHotkeys, defaults: defaults), defaults)
    }

    @Test("A saved shortcut reads back as the same combination")
    func roundTrip() throws {
        let (store, _) = try makeStore()
        try store.set(Self.combination, for: "com.example.app:Item-0")
        let data = try #require(store.rawBindings()["com.example.app:Item-0"])
        #expect(try HotkeyBindingStore.combination(from: data) == Self.combination)
    }

    @Test("The stored value is the JSON every earlier release wrote, so old shortcuts still load")
    func storedFormat() throws {
        let (store, defaults) = try makeStore()
        try store.set(Self.combination, for: "open")
        let stored = try #require(defaults.dictionary(forKey: Defaults.Key.menuBarItemHotkeys.rawValue) as? [String: Data])
        #expect(stored["open"] == (try JSONEncoder().encode(Self.combination)))
    }

    @Test("Clearing a shortcut removes its key and leaves the others")
    func clearing() throws {
        let (store, _) = try makeStore()
        try store.set(Self.combination, for: "kept")
        try store.set(Self.combination, for: "cleared")
        try store.set(nil, for: "cleared")
        #expect(Set(store.rawBindings().keys) == ["kept"])
    }

    @Test("Replacing every binding drops the ones left out")
    func replacing() throws {
        let (store, _) = try makeStore()
        try store.set(Self.combination, for: "old")
        let data = try JSONEncoder().encode(Self.combination)
        store.setRawBindings(["new": data])
        #expect(store.rawBindings() == ["new": data])
    }

    @Test("A stored JSON null reads as no shortcut, and nothing saved reads as empty")
    func emptyAndNull() throws {
        let (store, _) = try makeStore()
        #expect(store.rawBindings().isEmpty)
        #expect(try HotkeyBindingStore.combination(from: Data("null".utf8)) == nil)
    }
}
