//
//  AppSettings.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation

/// Top-level model for the app's settings.
///
/// Children are `@Observable`, so views track reads on the child property
/// they access. See `AppState`'s note for the one caveat.
@MainActor
@Observable
final class AppSettings {
    /// The model for the app's Advanced settings.
    let advanced = AdvancedSettings()

    /// The model for the app's General settings.
    let general = GeneralSettings()

    /// The model for the app's Hotkeys settings.
    let hotkeys = HotkeysSettings()

    /// The model for per-display Thaw Bar settings.
    let displaySettings = DisplaySettingsManager()

    /// The model for conditional menu bar item triggers.
    let triggers = MenuBarItemTriggersManager()

    @ObservationIgnored
    private(set) weak var appState: AppState?

    func performSetup(with appState: AppState) {
        self.appState = appState
        advanced.performSetup(with: appState)
        general.performSetup(with: appState)
        hotkeys.performSetup(with: appState)
        displaySettings.performSetup(with: appState)
        triggers.performSetup(with: appState)
    }
}
