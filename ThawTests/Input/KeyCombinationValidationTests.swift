//
//  KeyCombinationValidationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Saved and imported hotkeys can hold any number, so a bad key code must be refused, not trapped on.
@MainActor
@Suite("Key combination validation")
struct KeyCombinationValidationTests {
    private func decode(_ json: String) throws -> KeyCombination {
        try JSONDecoder().decode(KeyCombination.self, from: Data(json.utf8))
    }

    @Test("A negative key code is refused")
    func negativeKeyCodeIsRefused() {
        #expect(throws: DecodingError.self) {
            try decode("[-1,0]")
        }
    }

    @Test("A key code past what a key event carries is refused")
    func oversizedKeyCodeIsRefused() {
        #expect(throws: DecodingError.self) {
            try decode("[65536,0]")
        }
    }

    @Test("A real key code still decodes and round-trips")
    func validKeyCodeRoundTrips() throws {
        let combination = try decode("[0,9]")
        #expect(combination.key == .a)
        let data = try JSONEncoder().encode(combination)
        #expect(try JSONDecoder().decode(KeyCombination.self, from: data) == combination)
    }

    @Test("A malformed optional binding fails to decode instead of trapping")
    func malformedOptionalBindingThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyCombination?.self, from: Data("[-1,0]".utf8))
        }
    }

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

    @Test("The valid range matches what a key event can carry")
    func validRangeMatchesKeyEvents() {
        #expect(KeyCode(rawValue: 0).isValid)
        #expect(KeyCode(rawValue: Int(UInt16.max)).isValid)
        #expect(!KeyCode(rawValue: -1).isValid)
        #expect(!KeyCode(rawValue: Int(UInt16.max) + 1).isValid)
    }
}
