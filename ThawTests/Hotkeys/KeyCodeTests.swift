//
//  KeyCodeTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Carbon.HIToolbox
import Foundation
import Testing
@testable import Thaw

/// Covers ``KeyCode``'s Carbon raw values, its `Hashable`/`Codable`
/// conformances, and the string the hotkey recorder renders for a key.
///
/// The constants are compile-time `static let`s, so the raw-value cases are
/// cheap regression locks rather than logic tests. The string values are the
/// part with behaviour: `keyEquivalent` resolves through the *current*
/// keyboard layout, so its output cannot be asserted verbatim without pinning
/// the layout. What is pinned instead holds on any ASCII-capable layout — the
/// custom mapping table that bypasses the layout entirely, and the
/// empty-string fallback for a key the layout cannot resolve.
/// Pinned to the main actor and serialized: `keyEquivalent` reaches
/// `TISCopyCurrentASCIICapableKeyboardLayoutInputSource` and `UCKeyTranslate`,
/// which are not safe to call concurrently. XCTest ran this class's tests
/// serially and never exercised that; swift-testing parallelizes in-process
/// regardless of the scheme's own parallelization setting, and the Carbon
/// calls crash the host when they overlap.
@MainActor
@Suite("Key codes", .serialized)
struct KeyCodeTests {
    // MARK: Raw values

    @Test("Letter constants carry their Carbon raw values")
    func letterKeyCodes() {
        #expect(KeyCode.a.rawValue == kVK_ANSI_A)
        #expect(KeyCode.b.rawValue == kVK_ANSI_B)
        #expect(KeyCode.c.rawValue == kVK_ANSI_C)
        #expect(KeyCode.z.rawValue == kVK_ANSI_Z)
    }

    @Test("Number constants carry their Carbon raw values")
    func numberKeyCodes() {
        #expect(KeyCode.zero.rawValue == kVK_ANSI_0)
        #expect(KeyCode.one.rawValue == kVK_ANSI_1)
        #expect(KeyCode.nine.rawValue == kVK_ANSI_9)
    }

    @Test("Special-key constants carry their Carbon raw values")
    func specialKeyCodes() {
        #expect(KeyCode.space.rawValue == kVK_Space)
        #expect(KeyCode.tab.rawValue == kVK_Tab)
        #expect(KeyCode.returnKey.rawValue == kVK_Return)
        #expect(KeyCode.delete.rawValue == kVK_Delete)
    }

    @Test("A key code built from a raw value keeps it")
    func rawRepresentableInit() {
        #expect(KeyCode(rawValue: kVK_ANSI_A).rawValue == kVK_ANSI_A)
    }

    // MARK: Hashable

    @Test("Equal raw values compare and hash equally")
    func hashableUsesTheRawValue() {
        let fromConstant = KeyCode.a
        let fromRawValue = KeyCode(rawValue: kVK_ANSI_A)

        #expect(fromConstant == fromRawValue)
        #expect(fromConstant.hashValue == fromRawValue.hashValue)
    }

    @Test("Different keys are not equal")
    func differentCodesAreNotEqual() {
        #expect(KeyCode.a != KeyCode.b)
        #expect(KeyCode.one != KeyCode.two)
    }

    @Test("A key code deduplicates in a set")
    func useInSet() {
        var keySet: Set<KeyCode> = []
        keySet.insert(.a)
        keySet.insert(.b)
        keySet.insert(.a)

        #expect(keySet.count == 2)
        #expect(keySet.contains(.a))
        #expect(keySet.contains(.b))
        #expect(!keySet.contains(.c))
    }

    @Test("A key code works as a dictionary key")
    func useAsDictionaryKey() {
        var dictionary: [KeyCode: String] = [:]
        dictionary[.a] = "Letter A"
        dictionary[.space] = "Space Bar"

        #expect(dictionary[.a] == "Letter A")
        #expect(dictionary[.space] == "Space Bar")
        #expect(dictionary[.b] == nil)
    }

    // MARK: Codable

    // Not parameterized over `arguments:`. `KeyCode` is neither
    // `CustomStringConvertible` nor `CustomTestArgumentEncodable`, and
    // swift-testing crashes describing it as a test argument.

    @Test("A key code round-trips through Codable")
    func codableRoundTrip() throws {
        let original = KeyCode.a

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyCode.self, from: data)

        #expect(decoded == original)
        #expect(decoded.rawValue == original.rawValue)
    }

    @Test("Every kind of key round-trips through Codable")
    func codableRoundTripAcrossKinds() throws {
        for keyCode: KeyCode in [.a, .b, .space, .returnKey, .one] {
            let data = try JSONEncoder().encode(keyCode)
            let decoded = try JSONDecoder().decode(KeyCode.self, from: data)

            #expect(decoded == keyCode)
        }
    }

    // MARK: String value

    @Test("Keys with no printable form still render a glyph")
    func customMappedKeysRenderAGlyph() {
        // No printable layout representation exists for these, so a non-empty
        // stringValue can only have come from the custom mapping table.
        #expect(!KeyCode.space.stringValue.isEmpty)
        #expect(!KeyCode.escape.stringValue.isEmpty)
        #expect(!KeyCode.tab.stringValue.isEmpty)
        #expect(!KeyCode.delete.stringValue.isEmpty)
        #expect(!KeyCode.returnKey.stringValue.isEmpty)
    }

    @Test("A custom-mapped key does not fall through to the layout")
    func customMappingBypassesTheLayout() {
        // Escape has no printable equivalent on any layout, so stringValue
        // differing from keyEquivalent proves the mapping table won.
        #expect(KeyCode.escape.stringValue != KeyCode.escape.keyEquivalent)
    }

    @Test("An unmapped letter falls through to the layout")
    func unmappedLetterFallsThroughToTheLayout() {
        #expect(KeyCode.a.stringValue == KeyCode.a.keyEquivalent)
    }

    @Test("Arrow keys render a glyph")
    func arrowKeysRenderAGlyph() {
        #expect(!KeyCode.leftArrow.stringValue.isEmpty)
        #expect(!KeyCode.rightArrow.stringValue.isEmpty)
        #expect(!KeyCode.upArrow.stringValue.isEmpty)
        #expect(!KeyCode.downArrow.stringValue.isEmpty)
    }

    @Test("An unresolvable key code renders as empty rather than trapping")
    func unresolvableKeyCodeRendersEmpty() {
        // Out of range for any layout: UCKeyTranslate resolves nothing, and
        // there is no custom mapping to fall back on.
        let bogus = KeyCode(rawValue: 0x7FFF)

        #expect(bogus.keyEquivalent.isEmpty)
        #expect(bogus.stringValue.isEmpty)
    }
}
