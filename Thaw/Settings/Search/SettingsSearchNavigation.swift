//
//  SettingsSearchNavigation.swift
//  Project: Thaw
//
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
        navigationState.requestedSettingsSection = entry.sectionText
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
        navigationState.requestedSettingsSection = nil
        navigationState.settingsNavigationIdentifier = pane
    }

    /// The requested section, once, if tabFor finds a tab holding it.
    static func consumeSection<Tab>(
        navigationState: AppNavigationState,
        tabFor: (String) -> Tab?
    ) -> Tab? {
        guard let section = navigationState.requestedSettingsSection, let tab = tabFor(section) else {
            return nil
        }
        navigationState.requestedSettingsSection = nil
        return tab
    }

    /// The requested disclosure's tab, once, if tabFor finds one.
    static func consumeDisclosure<Tab>(
        navigationState: AppNavigationState,
        tabFor: (AppNavigationState.SettingsDisclosure) -> Tab?
    ) -> Tab? {
        guard let disclosure = navigationState.requestedSettingsDisclosure, let tab = tabFor(disclosure) else {
            return nil
        }
        navigationState.requestedSettingsDisclosure = nil
        return tab
    }
}
