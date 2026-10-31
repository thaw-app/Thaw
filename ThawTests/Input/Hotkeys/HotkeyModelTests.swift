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
import ThawUI

/// The hotkey model: its enabling, its owner callback and equality. ThawUI's tests cover keys and combinations.
@MainActor
@Suite("Hotkey model")
struct HotkeyTests {
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
