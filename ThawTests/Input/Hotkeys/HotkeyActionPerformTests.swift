//
//  HotkeyActionPerformTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

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
