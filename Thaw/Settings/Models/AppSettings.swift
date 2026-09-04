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
/// Now that its four children (`advanced`, `general`, `hotkeys`,
/// `displaySettings`) are `@Observable`, `AppSettings` itself is
/// `@Observable` too, with plain `let` children. The previous
/// `objectWillChange` forwarding block (each child's `objectWillChange`
/// re-published into this object's own `objectWillChange`) is gone: it
/// only existed to bridge each child's `ObservableObject` conformance up
/// through `AppSettings`. Views that read through an `@Observable`
/// `AppSettings` reference (or, transitively, through `AppState`) now have
/// their reads tracked directly on whichever child's property they access —
/// see `AppState`'s note on this for the one caveat.
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

    /// The shared app state.
    @ObservationIgnored
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the settings model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        advanced.performSetup(with: appState)
        general.performSetup(with: appState)
        hotkeys.performSetup(with: appState)
        displaySettings.performSetup(with: appState)
        triggers.performSetup(with: appState)
    }
}
