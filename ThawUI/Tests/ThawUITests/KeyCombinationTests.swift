//
//  KeyCombinationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import ThawUI

/// The modifier conversions between the shared mask and the Cocoa, CoreGraphics and Carbon flag sets.
@Suite("Hotkey modifiers")
struct ModifiersTests {
    private static let combinations: [Modifiers] = [
        [], .control, .option, .shift, .command,
        [.control, .option], [.shift, .command], [.control, .option, .shift, .command],
    ]

    @Test("The symbols follow Apple's display order whatever order they were added in")
    func symbolicOrder() {
        let modifiers: Modifiers = [.command, .shift, .option, .control]
        #expect(modifiers.symbolicValue == "⌃⌥⇧⌘")
        #expect(Modifiers.command.symbolicValue == "⌘")
        #expect(Modifiers().symbolicValue.isEmpty)
        #expect(Modifiers.canonicalOrder == [.control, .option, .shift, .command])
    }

    @Test("Cocoa flags round-trip", arguments: combinations)
    func cocoaRoundTrip(_ modifiers: Modifiers) {
        #expect(Modifiers(nsEventFlags: modifiers.nsEventFlags) == modifiers)
    }

    @Test("CoreGraphics flags round-trip", arguments: combinations)
    func coreGraphicsRoundTrip(_ modifiers: Modifiers) {
        #expect(Modifiers(cgEventFlags: modifiers.cgEventFlags) == modifiers)
    }

    @Test("Carbon flags round-trip", arguments: combinations)
    func carbonRoundTrip(_ modifiers: Modifiers) {
        #expect(Modifiers(carbonFlags: modifiers.carbonFlags) == modifiers)
    }

    @Test("Each modifier maps to the matching system flag")
    func individualFlags() {
        #expect(Modifiers.control.nsEventFlags == .control)
        #expect(Modifiers.option.cgEventFlags == .maskAlternate)
        #expect(Modifiers.shift.carbonFlags == shiftKey)
        #expect(Modifiers.command.carbonFlags == cmdKey)
        #expect(Modifiers.control.carbonFlags == controlKey)
        #expect(Modifiers.option.carbonFlags == optionKey)
    }

    @Test("Flags the mask does not track are ignored")
    func untrackedFlagsIgnored() {
        #expect(Modifiers(nsEventFlags: [.capsLock, .function, .command]) == .command)
        #expect(Modifiers(cgEventFlags: [.maskAlphaShift, .maskSecondaryFn]).isEmpty)
        #expect(Modifiers(carbonFlags: alphaLock).isEmpty)
    }
}

@Suite("Key code table")
struct KeyCodeTableTests {
    private static let namedKeys: [KeyCode] = [.a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z, .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .grave, .minus, .equal, .leftBracket, .rightBracket, .backslash, .semicolon, .quote, .comma, .period, .slash, .space, .tab, .returnKey, .delete, .forwardDelete, .escape, .help, .home, .end, .pageUp, .pageDown, .leftArrow, .rightArrow, .upArrow, .downArrow, .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20, .capsLock, .function, .control, .rightControl, .option, .rightOption, .shift, .rightShift, .command, .rightCommand, .keypad0, .keypad1, .keypad2, .keypad3, .keypad4, .keypad5, .keypad6, .keypad7, .keypad8, .keypad9, .keypadDecimal, .keypadPlus, .keypadMinus, .keypadMultiply, .keypadDivide, .keypadEquals, .keypadClear, .keypadEnter, .volumeUp, .volumeDown, .mute]

    @Test("Every named key has its own valid code")
    func distinctValidCodes() {
        #expect(!Self.namedKeys.contains { !$0.isValid })
        #expect(Set(Self.namedKeys).count == Self.namedKeys.count)
    }

    @Test("Named keys use the platform's virtual key codes")
    func platformCodes() {
        #expect(KeyCode.a.rawValue == 0)
        #expect(KeyCode.space.rawValue == 49)
        #expect(KeyCode.escape.rawValue == 53)
        #expect(KeyCode.f1.rawValue == 122)
    }

    @Test("The valid range matches what a key event can carry")
    func validRangeMatchesKeyEvents() {
        #expect(KeyCode(rawValue: 0).isValid)
        #expect(KeyCode(rawValue: Int(UInt16.max)).isValid)
        #expect(!KeyCode(rawValue: -1).isValid)
        #expect(!KeyCode(rawValue: Int(UInt16.max) + 1).isValid)
    }
}

@MainActor
@Suite("Key code labels")
struct KeyCodeLabelTests {
    private func label(_ key: KeyCode) -> String {
        key.stringValue(spaceName: "Barra")
    }

    @Test("The space bar shows the app's word for it")
    func spaceName() {
        #expect(label(.space) == "Barra")
    }

    @Test("Keys with an engraved glyph show that glyph")
    func engravedLabels() {
        #expect(label(.returnKey) == "⏎")
        #expect(label(.escape) == "⎋")
        #expect(label(.leftArrow) == "←")
        #expect(label(.command) == label(.rightCommand))
    }

    @Test("Function keys are numbered by their place in the row")
    func functionRow() {
        #expect(label(.f1) == "F1")
        #expect(label(.f12) == "F12")
        #expect(label(.f20) == "F20")
    }

    @Test("Keypad keys are enclosed so they differ from the main block")
    func keypadKeys() {
        #expect(label(.keypad5) == "5\u{20E3}")
        #expect(label(.keypadPlus) == "+\u{20E3}")
        #expect(label(.keypad5) != label(.five))
    }

    @Test("A letter falls back to what it types on the current layout")
    func letterUsesLayout() {
        #expect(label(.a) == KeyCode.a.keyEquivalent)
        #expect(KeyCode.a.keyEquivalent.count == 1)
    }
}

@MainActor
@Suite("Key combination")
struct KeyCombinationTests {
    private func decode(_ json: String) throws -> KeyCombination {
        try JSONDecoder().decode(KeyCombination.self, from: Data(json.utf8))
    }

    @Test("The display value joins the modifiers and the key")
    func displayValue() {
        let combination = KeyCombination(key: .space, modifiers: [.command, .shift])
        #expect(combination.displayValue(spaceName: "Space") == "⇧⌘ Space")
    }

    @Test("A combination made from a key event keeps its key and modifiers")
    func fromEvent() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "b",
            charactersIgnoringModifiers: "b",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_B)
        ))
        let combination = KeyCombination(event: event)
        #expect(combination.key == .b)
        #expect(combination.modifiers == [.option, .command])
    }

    @Test("Equal combinations hash alike")
    func hashing() {
        let combination = KeyCombination(key: .space, modifiers: [.control, .option])
        let same = KeyCombination(key: .space, modifiers: [.option, .control])
        #expect(same == combination)
        #expect(Set([same, combination]).count == 1)
        #expect(KeyCombination(key: .space, modifiers: .command) != combination)
    }

    /// What both apps have saved: a pair of raw values, in this order. These bytes must never change.
    @Test("A combination keeps the saved form of a key code then a modifier mask")
    func savedForm() throws {
        let combination = KeyCombination(key: .space, modifiers: [.control, .option])
        let data = try JSONEncoder().encode(combination)
        #expect(String(bytes: data, encoding: .utf8) == "[49,3]")
        #expect(try decode("[49,3]") == combination)
    }

    @Test("Key codes and modifiers keep their saved raw values")
    func savedRawValues() throws {
        #expect(try String(bytes: JSONEncoder().encode(KeyCode.a), encoding: .utf8) == "0")
        #expect(try String(bytes: JSONEncoder().encode(KeyCode.f1), encoding: .utf8) == "122")
        #expect(try String(bytes: JSONEncoder().encode(Modifiers.command), encoding: .utf8) == "8")
        #expect(Modifiers.control.rawValue == 1)
        #expect(Modifiers.option.rawValue == 2)
        #expect(Modifiers.shift.rawValue == 4)
        #expect(Modifiers.command.rawValue == 8)
    }

    @Test("Anything but a pair fails to decode", arguments: ["[49]", "[49,3,1]", "[]"])
    func wrongArity(json: String) {
        #expect(throws: DecodingError.self) {
            try decode(json)
        }
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

    @Test("Every modifier on F20 is a combination the system leaves free")
    func unusedKeyIsFree() {
        #expect(!KeyCombination(key: .f20, modifiers: [.control, .option, .shift, .command]).isSystemReserved)
    }

    @Test("Only enabled, complete entries of the system's list count as reserved")
    func reservedList() {
        let enabled: [String: Any] = [kHISymbolicHotKeyEnabled: true, kHISymbolicHotKeyCode: KeyCode.space.rawValue, kHISymbolicHotKeyModifiers: cmdKey]
        let disabled: [String: Any] = [kHISymbolicHotKeyEnabled: false, kHISymbolicHotKeyCode: KeyCode.a.rawValue, kHISymbolicHotKeyModifiers: cmdKey]
        let incomplete: [String: Any] = [kHISymbolicHotKeyEnabled: true, kHISymbolicHotKeyCode: KeyCode.b.rawValue]
        let reserved = KeyCombination.reservedKeyCombinations(fromSymbolicHotkeys: [enabled, disabled, incomplete, "not a hotkey"])
        #expect(reserved == [KeyCombination(key: .space, modifiers: .command)])
    }
}
