//
//  MenuBarBackgroundSettingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

struct MenuBarBackgroundSettingTests {
    @Test
    func `the background is on only when SkyLight's preference says so`() {
        #expect(MenuBarBackgroundSetting.isOn { $0 == MenuBarBackgroundSetting.key ? NSNumber(value: true) : nil })
        #expect(!MenuBarBackgroundSetting.isOn { _ in NSNumber(value: false) })
    }

    @Test
    func `an unset or unreadable preference counts as off`() {
        #expect(!MenuBarBackgroundSetting.isOn { _ in nil })
        #expect(!MenuBarBackgroundSetting.isOn { _ in "yes" })
    }

    @Test
    func `the live read takes the switch from the global domain`() {
        let global = CFPreferencesCopyAppValue(MenuBarBackgroundSetting.key as CFString, kCFPreferencesAnyApplication)
        #expect(MenuBarBackgroundSetting.isOn() == ((global as? NSNumber)?.boolValue ?? false))
    }
}
