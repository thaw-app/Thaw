//
//  HotkeyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Carbon.HIToolbox
import Foundation
import MenuBarModel
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

// Writing defaults posts a change notification the app observes on the main actor.
@MainActor
@Suite("Saved shortcuts")
struct HotkeyBindingStoreTests {
    private static let combination = KeyCombination(key: KeyCode(rawValue: 0x6A), modifiers: [.command, .option])

    private let suites = ScratchSuites(prefix: "HotkeyBindingStoreTests")

    private func makeStore() throws -> (HotkeyBindingStore, UserDefaults) {
        let defaults = try #require(suites.make())
        return (HotkeyBindingStore(key: .menuBarItemHotkeys, defaults: defaults), defaults)
    }

    @Test("A saved shortcut reads back as the same combination")
    func roundTrip() throws {
        let (store, _) = try makeStore()
        try store.set(Self.combination, for: "com.example.app:Item-0")
        let data = try #require(store.rawBindings()["com.example.app:Item-0"])
        #expect(try HotkeyBindingStore.combination(from: data) == Self.combination)
    }

    @Test("The stored value is the JSON every earlier release wrote, so old shortcuts still load")
    func storedFormat() throws {
        let (store, defaults) = try makeStore()
        try store.set(Self.combination, for: "open")
        let stored = try #require(defaults.dictionary(forKey: Defaults.Key.menuBarItemHotkeys.rawValue) as? [String: Data])
        #expect(stored["open"] == (try JSONEncoder().encode(Self.combination)))
    }

    @Test("Clearing a shortcut removes its key and leaves the others")
    func clearing() throws {
        let (store, _) = try makeStore()
        try store.set(Self.combination, for: "kept")
        try store.set(Self.combination, for: "cleared")
        try store.set(nil, for: "cleared")
        #expect(Set(store.rawBindings().keys) == ["kept"])
    }

    @Test("Replacing every binding drops the ones left out")
    func replacing() throws {
        let (store, _) = try makeStore()
        try store.set(Self.combination, for: "old")
        let data = try JSONEncoder().encode(Self.combination)
        store.setRawBindings(["new": data])
        #expect(store.rawBindings() == ["new": data])
    }

    @Test("A stored JSON null reads as no shortcut, and nothing saved reads as empty")
    func emptyAndNull() throws {
        let (store, _) = try makeStore()
        #expect(store.rawBindings().isEmpty)
        #expect(try HotkeyBindingStore.combination(from: Data("null".utf8)) == nil)
    }
}

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

/// Hotkey actions run against an AppState that was never set up, so nothing reaches the real menu bar.
/// Only the actions whose effect stays in settings are pressed here.
@MainActor
@Suite("Hotkey action perform", .serialized, .scratchDefaults)
struct HotkeyActionPerformTests {
    @Test("Profile and per-item actions do nothing themselves; their registrations handle them")
    func externallyHandledActionsDoNothing() {
        let appState = AppState()
        let manager = appState.menuBarManager
        let hiddenBefore = manager.sections.map(\.isHidden)
        let configurationsBefore = appState.settings.displaySettings.configurations

        HotkeyAction.profileApply.perform(appState: appState)
        HotkeyAction.openMenuBarItem.perform(appState: appState)

        #expect(manager.sections.map(\.isHidden) == hiddenBefore)
        #expect(manager.showOnHoverAllowed)
        #expect(appState.settings.displaySettings.configurations == configurationsBefore)
    }

    @Test("The Thaw Bar hotkey flips the Thaw Bar on the active display, and a second press flips it back")
    func thawBarHotkeyFlipsActiveDisplay() throws {
        let uuid = try #require(Bridging.getActiveMenuBarDisplayUUID(), "The test needs an active menu bar display")
        let appState = AppState()
        let displays = appState.settings.displaySettings
        let before = displays.configuration(forUUID: uuid).useThawBar

        HotkeyAction.enableThawBar.perform(appState: appState)
        #expect(displays.configuration(forUUID: uuid).useThawBar == !before)

        HotkeyAction.enableThawBar.perform(appState: appState)
        #expect(displays.configuration(forUUID: uuid).useThawBar == before)
    }
}

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
