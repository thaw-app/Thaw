//
//  AppNavigationState.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation

/// The model for app-wide navigation.
@MainActor
@Observable
final class AppNavigationState {
    /// A specific control group within a settings pane that a search result
    /// can request be revealed/expanded when navigating to that pane.
    nonisolated enum SettingsDisclosure: Hashable {
        case advancedLayoutControls
    }

    var isAppFrontmost = false
    var isSettingsPresented = false
    var isIceBarPresented = false
    var isSearchPresented = false
    var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general {
        didSet {
            // Reopen the settings window on the pane the user last used.
            Defaults.set(settingsNavigationIdentifier.rawValue, forKey: .lastSettingsPane)
        }
    }
    var requestedSettingsDisclosure: SettingsDisclosure?

    init() {
        if let rawValue = Defaults.string(forKey: .lastSettingsPane),
           let pane = SettingsNavigationIdentifier(rawValue: rawValue) {
            settingsNavigationIdentifier = pane
        }
    }
}
