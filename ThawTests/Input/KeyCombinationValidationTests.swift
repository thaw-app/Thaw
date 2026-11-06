//
//  KeyCombinationValidationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw
import ThawUI

/// Saved and imported hotkeys can hold any number, so registration must refuse a bad key code, not trap on it.
/// ThawUI's tests cover decoding.
@MainActor
@Suite("Key combination validation")
struct KeyCombinationValidationTests {
    @Test("Registration skips a key code Carbon can't take")
    func registrationSkipsInvalidKeyCode() {
        let combination = KeyCombination(key: KeyCode(rawValue: -1), modifiers: .command)
        #expect(HotkeyRegistry.carbonCodes(for: combination) == nil)
    }

    @Test("Registration converts a real key code exactly")
    func registrationConvertsValidKeyCode() throws {
        let combination = KeyCombination(key: .a, modifiers: .command)
        let codes = try #require(HotkeyRegistry.carbonCodes(for: combination))
        #expect(codes.keyCode == UInt32(KeyCode.a.rawValue))
        #expect(codes.modifiers == UInt32(Modifiers.command.carbonFlags))
    }
}
