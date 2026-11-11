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
    let general = GeneralSettings()

    let layout = LayoutSettings()

    let visibility = VisibilitySettings()

    let appearance = AppearanceSettings()

    let thawBar = ThawBarSettings()

    let spaces = SpacesSettings()

    let privacy = PrivacySettings()

    let tools = ToolsSettings()

    let widgets = WidgetsSettings()

    let launchAtLogin = LaunchAtLoginSetting()

    let hotkeys = HotkeysSettings()

    let displaySettings = DisplaySettingsManager()

    @ObservationIgnored
    private(set) weak var appState: AppState?

    func performSetup(with appState: AppState) {
        self.appState = appState
        layout.performSetup(with: appState)
        visibility.performSetup()
        appearance.performSetup()
        thawBar.performSetup()
        spaces.performSetup()
        privacy.performSetup()
        tools.performSetup()
        widgets.performSetup()
        general.performSetup(with: appState)
        hotkeys.performSetup(with: appState)
        displaySettings.performSetup(with: appState)
    }

    /// Reads the stored values again, in the settings process and after it wrote them.
    func loadStoredValues() {
        general.loadInitialState()
        layout.loadInitialState()
        visibility.loadInitialState()
        appearance.loadInitialState()
        thawBar.loadInitialState()
        spaces.loadInitialState()
        privacy.loadInitialState()
        tools.loadInitialState()
        widgets.loadInitialState()
    }
}
