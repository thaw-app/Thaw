//
//  HotkeysSettingsPersistenceTests.swift
//  Project: Thaw
//
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

    /// A binding that no longer decodes (downgrade, hand-edited plist, truncated
    /// write) is dropped on its own without aborting the load.
    @Test("A corrupt stored binding is skipped without losing the others")
    func corruptBindingIsSkippedWithoutLosingTheOthers() throws {
        try withScratchDefaults { _ in
            let good = KeyCombination(key: .f19, modifiers: [.command, .shift])
            let goodData = try JSONEncoder().encode(good)
            let stored: [String: Data] = [
                HotkeyAction.toggleHiddenSection.rawValue: Data("definitely not JSON".utf8),
                HotkeyAction.searchMenuBarItems.rawValue: goodData,
            ]
            Defaults.set(stored, forKey: .hotkeys)

            let settings = HotkeysSettings()

            #expect(settings.hotkey(withAction: .toggleHiddenSection)?.keyCombination == nil)
            #expect(settings.hotkey(withAction: .searchMenuBarItems)?.keyCombination == good)
        }
    }

    /// `null` is a valid encoding of an unbound hotkey, so it decodes and clears the
    /// binding, a different arm from the failure above.
    @Test("A stored null binding decodes to no binding")
    func storedNullBindingDecodesToNoBinding() throws {
        try withScratchDefaults { _ in
            let stored: [String: Data] = [
                HotkeyAction.toggleHiddenSection.rawValue: Data("null".utf8),
            ]
            Defaults.set(stored, forKey: .hotkeys)

            let settings = HotkeysSettings()

            #expect(settings.hotkey(withAction: .toggleHiddenSection)?.keyCombination == nil)
        }
    }

    @Test("An empty stored dictionary leaves every binding clear")
    func emptyStoredDictionaryLeavesEveryBindingClear() throws {
        try withScratchDefaults { _ in
            Defaults.set([String: Data](), forKey: .hotkeys)

            let settings = HotkeysSettings()

            #expect(settings.hotkeys.allSatisfy { $0.keyCombination == nil })
            #expect(!settings.hotkeys.isEmpty)
        }
    }
}
