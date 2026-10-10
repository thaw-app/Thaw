//
//  AppSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation

/// Child @Observable properties track reads through AppSettings or AppState directly; no forwarding is needed.
@MainActor
@Observable
final class AppSettings {
    let advanced = AdvancedSettings()

    let general = GeneralSettings()

    let launchAtLogin = LaunchAtLoginSetting()

    let hotkeys = HotkeysSettings()

    let displaySettings = DisplaySettingsManager()

    let automation = AutomationSettings()

    let automationHook = AutomationHookSettings()

    @ObservationIgnored
    private(set) weak var appState: AppState?

    func performSetup(with appState: AppState) {
        self.appState = appState
        advanced.performSetup(with: appState)
        general.performSetup(with: appState)
        hotkeys.performSetup(with: appState)
        displaySettings.performSetup(with: appState)
    }
}
