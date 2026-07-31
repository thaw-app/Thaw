//
//  HotkeysSettingsPersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Hotkey settings persistence", .serialized)
@MainActor
struct HotkeysSettingsPersistenceTests {
    @Test("Bindings load, update, and clear without app setup")
    func bindingsRoundTrip() throws {
        try withScratchDefaults { _ in
            let action = HotkeyAction.searchMenuBarItems
            let initial = KeyCombination(key: .f19, modifiers: [.command, .shift])
            let updated = KeyCombination(key: .f20, modifiers: [.control, .option])
            try Defaults.set(
                [action.rawValue: JSONEncoder().encode(initial)],
                forKey: .hotkeys
            )

            let settings = HotkeysSettings()
            let hotkey = try #require(settings.hotkey(withAction: action))
            #expect(hotkey.keyCombination == initial)

            hotkey.keyCombination = updated

            let storedData = try #require(
                Defaults.dictionary(forKey: .hotkeys)?[action.rawValue] as? Data
            )
            #expect(try JSONDecoder().decode(KeyCombination.self, from: storedData) == updated)

            hotkey.keyCombination = nil

            #expect(Defaults.dictionary(forKey: .hotkeys)?[action.rawValue] == nil)
        }
    }
}
