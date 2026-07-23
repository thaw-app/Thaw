//
//  SettingsSearchNavigation.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Coordinates settings search and sidebar selection so disclosure requests
/// cannot leak into a later, unrelated navigation.
@MainActor
enum SettingsSearchNavigation {
    static func selectSearchResult(
        _ entry: SearchEntry,
        navigationState: AppNavigationState,
        query: inout String
    ) {
        navigationState.requestedSettingsDisclosure = entry.disclosure
        navigationState.settingsNavigationIdentifier = entry.pane
        query = ""
    }

    static func selectSidebarPane(
        _ pane: SettingsNavigationIdentifier,
        navigationState: AppNavigationState
    ) {
        guard navigationState.settingsNavigationIdentifier != pane else {
            return
        }
        navigationState.requestedSettingsDisclosure = nil
        navigationState.settingsNavigationIdentifier = pane
    }

    static func consumeDisclosure(
        _ disclosure: AppNavigationState.SettingsDisclosure,
        navigationState: AppNavigationState
    ) -> Bool {
        guard navigationState.requestedSettingsDisclosure == disclosure else {
            return false
        }
        navigationState.requestedSettingsDisclosure = nil
        return true
    }
}
