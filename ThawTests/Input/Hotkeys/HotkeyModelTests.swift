//
//  HotkeyModelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Carbon.HIToolbox
import Testing
@testable import Thaw

/// The modifier conversions between Thaw's own mask and the Cocoa, CoreGraphics and Carbon flag sets.
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

    @Test("Flags Thaw does not track are ignored")
    func untrackedFlagsIgnored() {
        #expect(Modifiers(nsEventFlags: [.capsLock, .function, .command]) == .command)
        #expect(Modifiers(cgEventFlags: [.maskAlphaShift, .maskSecondaryFn]).isEmpty)
        #expect(Modifiers(carbonFlags: alphaLock).isEmpty)
    }
}

/// How keys are labelled for display.
@MainActor
@Suite("Key code labels")
struct KeyCodeLabelTests {
    @Test("Keys with an engraved glyph show that glyph")
    func engravedLabels() {
        #expect(KeyCode.space.stringValue == "Space")
        #expect(KeyCode.returnKey.stringValue == "⏎")
        #expect(KeyCode.escape.stringValue == "⎋")
        #expect(KeyCode.leftArrow.stringValue == "←")
        #expect(KeyCode.command.stringValue == KeyCode.rightCommand.stringValue)
    }

    @Test("Function keys are numbered by their place in the row")
    func functionRow() {
        #expect(KeyCode.f1.stringValue == "F1")
        #expect(KeyCode.f12.stringValue == "F12")
        #expect(KeyCode.f20.stringValue == "F20")
    }

    @Test("Keypad keys are enclosed so they differ from the main block")
    func keypadKeys() {
        #expect(KeyCode.keypad5.stringValue == "5\u{20E3}")
        #expect(KeyCode.keypadPlus.stringValue == "+\u{20E3}")
        #expect(KeyCode.keypad5.stringValue != KeyCode.five.stringValue)
    }

    @Test("A letter falls back to what it types on the current layout")
    func letterUsesLayout() {
        // The label is whatever the ASCII-capable layout types, never a fixed glyph.
        #expect(KeyCode.a.stringValue == KeyCode.a.keyEquivalent)
    }
}

/// The hotkey model: display, codable form and equality.
@MainActor
@Suite("Hotkey model")
struct HotkeyTests {
    @Test("The display value joins the modifiers and the key")
    func displayValue() {
        let combination = KeyCombination(key: .space, modifiers: [.command, .shift])
        #expect(combination.displayValue == "⇧⌘ Space")
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

    @Test("A combination with the wrong number of values fails to decode")
    func wrongArity() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyCombination.self, from: Data("[0]".utf8))
        }
    }

    @Test("A hotkey with no app state stays disabled")
    func disabledWithoutAppState() {
        let hotkey = Hotkey(action: .toggleHiddenSection, keyCombination: KeyCombination(key: .h, modifiers: .command))
        hotkey.enable()
        #expect(!hotkey.isEnabled)
        hotkey.disable()
        #expect(!hotkey.isEnabled)
    }

    @Test("Changing the combination tells the owner after it is stored")
    func changeCallback() {
        let hotkey = Hotkey(action: .toggleSwap)
        var seen: [KeyCombination?] = []
        hotkey.keyCombinationDidChange = { [unowned hotkey] in seen.append(hotkey.keyCombination) }
        let combination = KeyCombination(key: .s, modifiers: .control)
        hotkey.keyCombination = combination
        hotkey.keyCombination = nil
        #expect(seen == [combination, nil])
        #expect(!hotkey.isEnabled)
    }

    @Test("Hotkeys are equal when action and combination match")
    func equality() {
        let combination = KeyCombination(key: .z, modifiers: .command)
        let first = Hotkey(action: .toggleZenMode, keyCombination: combination)
        let second = Hotkey(action: .toggleZenMode, keyCombination: combination)
        let other = Hotkey(action: .toggleSwap, keyCombination: combination)
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(first != other)
        #expect(Set([first, second, other]).count == 2)
    }

    @Test("The settings pane lists every action but the externally handled ones")
    func settingsActions() {
        let actions = HotkeyAction.settingsActions
        #expect(!actions.contains(.profileApply))
        #expect(!actions.contains(.openMenuBarItem))
        #expect(actions.count == HotkeyAction.allCases.count - 2)
    }

    @Test("Hotkey actions keep the raw values saved settings use")
    func rawValues() {
        #expect(HotkeyAction(rawValue: "EnableIceBar") == .enableThawBar)
        #expect(HotkeyAction.toggleHiddenSection.rawValue == "ToggleHiddenSection")
    }

    @Test("URL actions map to their hotkey actions, except those with their own window")
    func urlActions() {
        #expect(SettingsURIAction.toggleHidden.hotkeyAction == .toggleHiddenSection)
        #expect(SettingsURIAction.toggleAlwaysHidden.hotkeyAction == .toggleAlwaysHiddenSection)
        #expect(SettingsURIAction.toggleSwap.hotkeyAction == .toggleSwap)
        #expect(SettingsURIAction.search.hotkeyAction == .searchMenuBarItems)
        #expect(SettingsURIAction.toggleApplicationMenus.hotkeyAction == .toggleApplicationMenus)
        #expect(SettingsURIAction.toggleZenMode.hotkeyAction == .toggleZenMode)
        #expect(SettingsURIAction.toggleLayoutEditor.hotkeyAction == .toggleLayoutEditor)
        #expect(SettingsURIAction.openSettings.hotkeyAction == nil)
        #expect(SettingsURIAction.itemHints.hotkeyAction == nil)
    }
}

/// Registry bookkeeping that never reaches Carbon.
@MainActor
@Suite("Hotkey registry bookkeeping")
struct HotkeyRegistryBookkeepingTests {
    @Test("A hotkey without a combination is refused before anything is installed")
    func refusesMissingCombination() {
        let registry = HotkeyRegistry()
        var ran = false
        let id = registry.register(hotkey: Hotkey(action: .toggleSwap), eventKind: .keyDown) { ran = true }
        #expect(id == nil)
        #expect(!ran)
    }

    @Test("A key code Carbon cannot take is refused")
    func refusesBadKeyCode() {
        let registry = HotkeyRegistry()
        let hotkey = Hotkey(action: .toggleSwap, keyCombination: KeyCombination(key: KeyCode(rawValue: 70000), modifiers: .command))
        #expect(registry.register(hotkey: hotkey, eventKind: .keyUp) {} == nil)
    }

    @Test("Unregistering an unknown id does nothing")
    func unregisterUnknown() {
        let registry = HotkeyRegistry()
        registry.unregister(12345)
        let hotkey = Hotkey(action: .toggleSwap)
        #expect(registry.register(hotkey: hotkey, eventKind: .keyDown) {} == nil)
    }
}
