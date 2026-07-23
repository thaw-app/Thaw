//
//  AppNavigationState.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine

/// The model for app-wide navigation.
@MainActor
final class AppNavigationState: ObservableObject {
    /// A specific control group within a settings pane that a search result
    /// can request be revealed/expanded when navigating to that pane.
    nonisolated enum SettingsDisclosure: Hashable {
        case advancedLayoutControls
    }

    @Published var isAppFrontmost = false
    @Published var isSettingsPresented = false
    @Published var isIceBarPresented = false
    @Published var isSearchPresented = false
    @Published var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general
    @Published var requestedSettingsDisclosure: SettingsDisclosure?
}
