//
//  SettingsPaneTabs.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// A page's tabs, in a section header so the grouped form gives them no card.
/// A search result opens the tab holding its section or its disclosure.
struct SettingsPaneTabs<Tab: ThawTab>: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: Tab
    let tabs: [Tab]
    /// The tab that holds a search result's section, or nil when none does.
    let tabForSection: (String) -> Tab?
    /// The tab a search result's disclosure opens, or nil when none does.
    let tabForDisclosure: (AppNavigationState.SettingsDisclosure) -> Tab?

    init(
        selection: Binding<Tab>,
        tabs: [Tab],
        tabForSection: @escaping (String) -> Tab? = { _ in nil },
        tabForDisclosure: @escaping (AppNavigationState.SettingsDisclosure) -> Tab? = { _ in nil }
    ) {
        _selection = selection
        self.tabs = tabs
        self.tabForSection = tabForSection
        self.tabForDisclosure = tabForDisclosure
    }

    var body: some View {
        ThawSection {
            ThawTabStrip(selection: $selection, tabs: tabs)
                .frame(maxWidth: .infinity)
                .onChange(of: appState.navigationState.requestedSettingsSection, initial: true) { _, _ in
                    if let tab = SettingsSearchNavigation.consumeSection(
                        navigationState: appState.navigationState,
                        tabFor: tabForSection
                    ) {
                        selection = tab
                    }
                }
                .onChange(of: appState.navigationState.requestedSettingsDisclosure, initial: true) { _, _ in
                    if let tab = SettingsSearchNavigation.consumeDisclosure(
                        navigationState: appState.navigationState,
                        tabFor: tabForDisclosure
                    ) {
                        selection = tab
                    }
                }
        } content: {
            EmptyView()
        }
    }
}
