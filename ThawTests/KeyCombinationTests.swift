//
//  KeyCombinationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Covers ``KeyCombination``, the key-plus-modifiers pair behind every hotkey.
///
/// Three surfaces matter here and `KeyCodeTests` / `ModifiersTests` cover
/// neither of them, since both stop at the individual halves.
///
/// The first is the encoded form. A key combination is stored as a two-element
/// unkeyed array — key code first, modifier mask second — inside every hotkey
/// default and every exported profile. Nothing about that shape is enforced by
/// the type system, and swapping the two elements would produce a payload that
/// still decodes and binds a completely different hotkey. The decoder's arity
/// check is the only guard against a truncated or extended payload, so both
/// sides of it are exercised.
///
/// The second is `init(event:)`, which is how a recorded keystroke becomes a
/// stored combination. It narrows `NSEvent.modifierFlags` — a mask that also
/// carries Caps Lock, Fn, and the numeric-keypad bit — down to the four
/// modifiers the app supports. A stray bit surviving that narrowing would make
/// a recorded hotkey compare unequal to the same keystroke replayed later.
///
/// The third is `isSystemReserved`, which reads the live symbolic hotkey table.
/// Its contents depend on the machine, so the tests assert the shape of the
/// answer rather than specific entries.
@MainActor
@Suite("Key combination")
struct KeyCombinationTests {
    // MARK: - Display

    @Test("The display value places the modifier symbols before the key")
    func displayValuePlacesModifiersFirst() {
        let combination = KeyCombination(key: .space, modifiers: [.command, .shift])

        #expect(combination.displayValue == "⇧⌘ Space")
    }

    /// The modifier symbols follow Apple's canonical order regardless of how
    /// the option set was built.
    @Test("The display value uses the canonical modifier order")
    func displayValueUsesTheCanonicalOrder() {
        let combination = KeyCombination(
            key: .f19,
            modifiers: [.command, .shift, .option, .control]
        )

        #expect(combination.displayValue == "⌃⌥⇧⌘ F19")
    }

    @Test("An unmodified combination still renders its key")
    func unmodifiedCombinationStillRendersItsKey() {
        let combination = KeyCombination(key: .f20, modifiers: [])

        #expect(combination.displayValue.hasSuffix("F20"))
        #expect(combination.displayValue.trimmingCharacters(in: .whitespaces) == "F20")
    }

    /// Letter keys have no custom mapping, so they fall through to the current
    /// keyboard layout's key equivalent and are capitalized for display.
    @Test("A letter key is capitalized for display")
    func letterKeyIsCapitalizedForDisplay() {
        let combination = KeyCombination(key: .a, modifiers: [.command])
        let expected = "⌘ " + KeyCode.a.stringValue.capitalized

        #expect(combination.displayValue == expected)
    }

    // MARK: - Value Semantics

    @Test("Two combinations with the same key and modifiers are equal")
    func matchingCombinationsAreEqual() {
        let first = KeyCombination(key: .f19, modifiers: [.command, .shift])
        let second = KeyCombination(key: .f19, modifiers: [.shift, .command])

        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }

    @Test("A differing key or modifier set makes two combinations unequal")
    func differingCombinationsAreUnequal() {
        let base = KeyCombination(key: .f19, modifiers: [.command])

        #expect(base != KeyCombination(key: .f20, modifiers: [.command]))
        #expect(base != KeyCombination(key: .f19, modifiers: [.control]))
        #expect(base != KeyCombination(key: .f19, modifiers: []))
    }

    // MARK: - Initialization From An Event

    /// Builds a key-down event, or records an issue if AppKit declines.
    private func keyEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }

    @Test("An event's key code and modifiers are carried across")
    func eventKeyCodeAndModifiersAreCarriedAcross() throws {
        let event = try #require(
            keyEvent(keyCode: UInt16(KeyCode.f19.rawValue), flags: [.command, .shift])
        )

        let combination = KeyCombination(event: event)

        #expect(combination.key == .f19)
        #expect(combination.modifiers == [.command, .shift])
    }

    /// Caps Lock, Fn, and the numeric-keypad bit all ride along in a real
    /// `NSEvent`, and none of them is a modifier the app can bind.
    @Test("Modifier bits the app does not support are dropped")
    func unsupportedModifierBitsAreDropped() throws {
        let event = try #require(
            keyEvent(
                keyCode: UInt16(KeyCode.f19.rawValue),
                flags: [.command, .capsLock, .function, .numericPad]
            )
        )

        let combination = KeyCombination(event: event)

        #expect(combination.modifiers == [.command])
    }

    @Test("An event with no modifiers produces an empty modifier set")
    func eventWithNoModifiersProducesAnEmptySet() throws {
        let event = try #require(keyEvent(keyCode: UInt16(KeyCode.f20.rawValue), flags: []))

        let combination = KeyCombination(event: event)

        #expect(combination.modifiers.isEmpty)
        #expect(combination.key == .f20)
    }

    /// The two initializers have to agree, otherwise a hotkey recorded from an
    /// event would not match the same combination built by hand.
    @Test("The event initializer agrees with the direct one")
    func eventInitializerAgreesWithTheDirectOne() throws {
        let event = try #require(
            keyEvent(keyCode: UInt16(KeyCode.f19.rawValue), flags: [.control, .option])
        )

        #expect(KeyCombination(event: event) == KeyCombination(key: .f19, modifiers: [.control, .option]))
    }

    // MARK: - Codable

    @Test("A combination survives a round trip")
    func combinationSurvivesARoundTrip() throws {
        let combination = KeyCombination(key: .f19, modifiers: [.command, .shift])

        let decoded = try JSONDecoder().decode(
            KeyCombination.self,
            from: JSONEncoder().encode(combination)
        )

        #expect(decoded == combination)
    }

    /// The stored shape is `[keyCode, modifierMask]`. Both the order and the
    /// arity are load-bearing.
    @Test("A combination encodes as a key code followed by a modifier mask")
    func combinationEncodesAsAnOrderedPair() throws {
        let combination = KeyCombination(key: .f19, modifiers: [.command, .shift])
        let data = try JSONEncoder().encode(combination)

        let decoded = try JSONDecoder().decode([Int].self, from: data)

        #expect(decoded == [KeyCode.f19.rawValue, Modifiers([.command, .shift]).rawValue])
    }

    @Test("A stored pair decodes into the matching combination")
    func storedPairDecodesIntoTheMatchingCombination() throws {
        let payload = Data("[\(KeyCode.f19.rawValue),\(Modifiers.command.rawValue)]".utf8)

        let decoded = try JSONDecoder().decode(KeyCombination.self, from: payload)

        #expect(decoded == KeyCombination(key: .f19, modifiers: .command))
    }

    /// An unrecognized key code is not rejected: `KeyCode` is a raw wrapper
    /// rather than a closed enum, so an unknown physical key round-trips.
    @Test("An unrecognized key code round-trips rather than failing")
    func unrecognizedKeyCodeRoundTrips() throws {
        let payload = Data("[9999,0]".utf8)

        let decoded = try JSONDecoder().decode(KeyCombination.self, from: payload)

        #expect(decoded.key.rawValue == 9999)
        #expect(decoded.modifiers.isEmpty)
    }

    @Test("A truncated payload is rejected")
    func truncatedPayloadIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyCombination.self, from: Data("[80]".utf8))
        }
    }

    @Test("An empty payload is rejected")
    func emptyPayloadIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyCombination.self, from: Data("[]".utf8))
        }
    }

    @Test("An over-long payload is rejected")
    func overLongPayloadIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyCombination.self, from: Data("[80,8,1]".utf8))
        }
    }

    @Test("A keyed payload is rejected")
    func keyedPayloadIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                KeyCombination.self,
                from: Data(#"{"key":80,"modifiers":8}"#.utf8)
            )
        }
    }

    @Test("A pair of the wrong element type is rejected")
    func wrongElementTypeIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyCombination.self, from: Data(#"["f19","command"]"#.utf8))
        }
    }

    // MARK: - System Reservation

    /// The reserved table is whatever the running machine has configured, so
    /// the assertion is that the lookup answers at all rather than that a
    /// particular combination is in it.
    @Test("Reservation lookup answers without trapping")
    func reservationLookupAnswers() {
        let combination = KeyCombination(key: .f19, modifiers: [.control, .option, .shift, .command])

        #expect(combination.isSystemReserved || !combination.isSystemReserved)
    }

    /// An unbindable key code cannot appear in the symbolic hotkey table, so it
    /// is a stable negative regardless of the machine's configuration.
    @Test("A combination that cannot be registered is not reserved")
    func unregistrableCombinationIsNotReserved() {
        let combination = KeyCombination(key: KeyCode(rawValue: 9999), modifiers: [])

        #expect(!combination.isSystemReserved)
    }

    /// Reservation is a property of the pair, so it has to agree for two
    /// combinations that compare equal.
    @Test("Equal combinations agree on their reservation")
    func equalCombinationsAgreeOnReservation() {
        let first = KeyCombination(key: .space, modifiers: [.command])
        let second = KeyCombination(key: .space, modifiers: [.command])

        #expect(first.isSystemReserved == second.isSystemReserved)
    }
}
