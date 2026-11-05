//
//  HotkeyRegistryLifetimeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw
import ThawUI

/// What a registry leaves with Carbon when it goes away. These claim a real combination that no other test uses.
@MainActor
@Suite("Hotkey registry lifetime", .serialized)
struct HotkeyRegistryLifetimeTests {
    private static let combination = KeyCombination(key: KeyCode(rawValue: 0x69), modifiers: [.command, .option, .control, .shift])

    private func claim(in registry: HotkeyRegistry) -> UInt32? {
        registry.register(hotkey: Hotkey(action: .toggleSwap, keyCombination: Self.combination), eventKind: .keyDown) {}
    }

    @Test("A registry that goes away gives its combinations back")
    func releasesItsCombinations() throws {
        do {
            let leaving = HotkeyRegistry()
            try #require(claim(in: leaving) != nil)
        }
        let next = HotkeyRegistry()
        let id = try #require(claim(in: next))
        next.unregister(id)
    }

    /// Carbon refuses a second handler with the same callback and context, here the registry's address.
    @Test("A new registry can install its handler at a freed registry's address")
    func removesItsHandler() throws {
        for _ in 0 ..< 50 {
            let registry = HotkeyRegistry()
            let id = try #require(claim(in: registry))
            registry.unregister(id)
        }
    }
}
