//
//  SettingsCloseDeactivationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Closing Settings")
struct SettingsCloseDeactivationTests {
    @Test("Settings on its own hands focus back, with the window still tracked as open")
    func settingsAlone() {
        #expect(AppState.shouldDeactivateAfterSettingsClosed(openWindows: [.settings], pendingWindows: []))
    }

    @Test("Another open or pending window keeps Thaw in front")
    func otherWindowKeepsFocus() {
        #expect(!AppState.shouldDeactivateAfterSettingsClosed(openWindows: [.settings, .whatsNew], pendingWindows: []))
        #expect(!AppState.shouldDeactivateAfterSettingsClosed(openWindows: [.settings], pendingWindows: [.acknowledgements]))
    }
}
