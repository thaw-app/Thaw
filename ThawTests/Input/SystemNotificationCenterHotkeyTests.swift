//
//  SystemNotificationCenterHotkeyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Tests for matching a key event against the system's notification-center
/// shortcut.
@Suite("Notification Center hotkey matching")
struct SystemNotificationCenterHotkeyTests {
    private let hotkey = SystemNotificationCenterHotkey(
        keyCode: 45,
        flags: [.maskControl, .maskAlternate]
    )

    @Test("Exact key and modifiers match")
    func exactMatch() {
        #expect(hotkey.matches(keyCode: 45, flags: [.maskControl, .maskAlternate]))
    }

    @Test("A different key does not match")
    func differentKeyDoesNotMatch() {
        let matches = hotkey.matches(keyCode: 46, flags: [.maskControl, .maskAlternate])
        #expect(!matches)
    }

    @Test("Missing preferences use Fn-N without taking over the bare Globe key")
    func systemDefault() throws {
        let shortcut = try #require(SystemNotificationCenterHotkey.configured(from: [:]))
        #expect(shortcut.matches(keyCode: 45, flags: [.maskSecondaryFn]))
        #expect(!shortcut.matches(keyCode: 63, flags: [.maskSecondaryFn]))
        #expect(!shortcut.matches(keyCode: 45, flags: []))
    }

    @Test("A custom shortcut keeps Fn-N available too")
    func customAndDefaultShortcuts() {
        let flags = CGEventFlags([.maskControl, .maskAlternate]).rawValue
        let table: [String: Any] = ["163": ["enabled": true, "value": ["parameters": [UInt64(110), 45, flags]]]]
        #expect(SystemNotificationCenterHotkey.shortcuts(from: table) == [hotkey, .systemDefault])
        #expect(SystemNotificationCenterHotkey.shortcuts(from: [:]) == [.systemDefault])
        #expect(SystemNotificationCenterHotkey.shortcuts(from: ["163": ["enabled": false]]).isEmpty)
    }

    @Test("An explicitly disabled shortcut stays disabled")
    func disabledShortcut() {
        #expect(SystemNotificationCenterHotkey.configured(from: ["163": ["enabled": false]]) == nil)
    }

    @Test("Unassigned and out-of-range key codes are not replayed", arguments: [-1, 65535, 65536])
    func invalidKeyCode(keyCode: Int) {
        let table: [String: Any] = ["163": ["enabled": true, "value": ["parameters": [0, keyCode, 0]]]]
        #expect(SystemNotificationCenterHotkey.configured(from: table) == nil)
    }

    @Test("Preferences preserve the configured Fn modifier")
    func configuredFunctionModifier() throws {
        let flags = CGEventFlags.maskSecondaryFn.rawValue
        let table: [String: Any] = ["163": ["enabled": true, "value": ["parameters": [UInt64(110), 45, flags]]]]
        let shortcut = try #require(SystemNotificationCenterHotkey.configured(from: table))
        #expect(shortcut == .systemDefault)
    }

    @Test("Fn-N matches the system Notification Center shortcut")
    func functionModifierIsPreserved() {
        let shortcut = SystemNotificationCenterHotkey(keyCode: 45, flags: [.maskSecondaryFn])
        #expect(shortcut.matches(keyCode: 45, flags: [.maskSecondaryFn]))
        #expect(!shortcut.matches(keyCode: 45, flags: []))
        #expect(!shortcut.matches(keyCode: 45, flags: [.maskSecondaryFn, .maskShift]))
    }

    @Test("Fn does not turn an unrelated chord into the configured shortcut")
    func functionModifierIsNotIgnored() {
        #expect(!hotkey.matches(keyCode: 45, flags: [.maskControl, .maskAlternate, .maskSecondaryFn]))
    }

    @Test("A missing modifier does not match")
    func missingModifierDoesNotMatch() {
        let matches = hotkey.matches(keyCode: 45, flags: [.maskControl])
        #expect(!matches)
    }

    @Test("An extra tracked modifier does not match")
    func extraModifierDoesNotMatch() {
        let matches = hotkey.matches(keyCode: 45, flags: [.maskControl, .maskAlternate, .maskCommand])
        #expect(!matches)
    }

    @Test("Untracked modifiers are ignored")
    func untrackedModifiersIgnored() {
        #expect(
            hotkey.matches(
                keyCode: 45,
                flags: [.maskControl, .maskAlternate, .maskAlphaShift]
            )
        )
    }
}
