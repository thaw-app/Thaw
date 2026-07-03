//
//  SettingsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    let appState: AppState
    @ObservedObject var navigationState: AppNavigationState

    @StateObject private var searchModel = SearchModel()

    private var isSearching: Bool {
        !searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            settingsPane
                .id(navigationState.settingsNavigationIdentifier)
        }
        .navigationTitle(navigationState.settingsNavigationIdentifier.localized)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchModel.searchText)

            Group {
                if isSearching {
                    if searchModel.displayedGroups.isEmpty {
                        SearchEmptyView()
                    } else {
                        SearchResultsList(groups: searchModel.displayedGroups) { entry in
                            navigate(to: entry.pane)
                        }
                    }
                } else {
                    SettingsSidebarPaneList(
                        navigationState: navigationState
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewColumnWidth(ideal: 200, max: 240)
        .onChange(of: searchModel.searchText, initial: true) {
            searchModel.updateDisplayedItems()
        }
    }

    /// Switches the detail pane to `pane` and clears the search query so the
    /// normal pane list returns with the new pane selected.
    private func navigate(to pane: SettingsNavigationIdentifier) {
        if navigationState.settingsNavigationIdentifier != pane {
            navigationState.settingsNavigationIdentifier = pane
        }
        searchModel.searchText = ""
    }

    @ViewBuilder
    private var settingsPane: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .general:
            GeneralSettingsPane(settings: appState.settings.general)
        case .displays:
            DisplaySettingsPane(displaySettings: appState.settings.displaySettings)
        case .menuBarLayout:
            MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane(appearanceManager: appState.appearanceManager)
        case .hotkeys:
            HotkeysSettingsPane(settings: appState.settings.hotkeys)
        case .profiles:
            ProfileSettingsPane(profileManager: appState.profileManager)
        case .advanced:
            AdvancedSettingsPane(settings: appState.settings.advanced)
        case .automation:
            AutomationSettingsPane()
        case .about:
            AboutSettingsPane(updatesManager: appState.updatesManager)
        }
    }
}

// MARK: - SettingsSidebarPaneList

/// The default settings sidebar navigation list.
private struct SettingsSidebarPaneList: View {
    @ObservedObject var navigationState: AppNavigationState

    var body: some View {
        let selection = Binding<SettingsNavigationIdentifier>(
            get: { navigationState.settingsNavigationIdentifier },
            set: { newValue in
                if navigationState.settingsNavigationIdentifier != newValue {
                    Task { @MainActor in
                        navigationState.settingsNavigationIdentifier = newValue
                    }
                }
            }
        )

        List(selection: selection) {
            Section {
                ForEach(SettingsNavigationIdentifier.allCases) { identifier in
                    Label {
                        Text(identifier.localized)
                    } icon: {
                        identifier.iconResource.view
                    }
                    .tag(identifier)
                }
            }
        }
        .listStyle(.sidebar)
    }
}
