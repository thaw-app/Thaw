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
    let navigationState: AppNavigationState
    @State private var searchModel = SearchModel()

    private var allSections: [SettingsNavigationIdentifier] {
        SettingsNavigationIdentifier.allCases
    }

    private var currentSectionIndex: Int? {
        allSections.firstIndex(of: navigationState.settingsNavigationIdentifier)
    }

    private var isFirstSection: Bool {
        currentSectionIndex == 0
    }

    private var isLastSection: Bool {
        currentSectionIndex == allSections.count - 1
    }

    var body: some View {
        if appState.settings.general.simpleMode {
            simpleMode
                .environment(\.settingsDescriptionsVisible, appState.settings.general.showSettingDescriptions)
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                settingsPane
                    .id(navigationState.settingsNavigationIdentifier)
            }
            .navigationTitle(navigationState.settingsNavigationIdentifier.localized)
            .environment(\.settingsDescriptionsVisible, appState.settings.general.showSettingDescriptions)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button(action: navigateBack) {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(isFirstSection)

                        Button(action: navigateForward) {
                            Label("Forward", systemImage: "chevron.right")
                        }
                        .disabled(isLastSection)
                    }
                    .controlGroupStyle(.navigation)
                }
            }
        }
    }

    /// Simple Mode's overview, or the one pane something explicitly asked for.
    ///
    /// There is no sidebar at all here: one screen is the whole point of Simple
    /// Mode, and a sidebar listing a single item is just a sidebar. But flows
    /// outside the window — a trigger notification, a settings link — still
    /// navigate to a specific pane, and dropping them on the overview opens the
    /// wrong destination. Honour the request, with a way back to the overview.
    @ViewBuilder
    private var simpleMode: some View {
        if navigationState.settingsNavigationIdentifier == .general {
            SimpleModeSettingsPane(
                itemManager: appState.itemManager,
                updatesManager: appState.updatesManager,
                settings: appState.settings.general
            )
            .navigationTitle("Settings")
        } else {
            settingsPane
                .id(navigationState.settingsNavigationIdentifier)
                .navigationTitle(navigationState.settingsNavigationIdentifier.localized)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            navigationState.settingsNavigationIdentifier = .general
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
        }
    }

    private var sidebar: some View {
        // Use a Binding that wraps the navigation state to ensure updates happen
        // on the main thread and avoid view update warnings.
        let selection = Binding<SettingsNavigationIdentifier>(
            get: { navigationState.settingsNavigationIdentifier },
            set: { newValue in
                if navigationState.settingsNavigationIdentifier != newValue {
                    Task { @MainActor in
                        SettingsSearchNavigation.selectSidebarPane(
                            newValue,
                            navigationState: navigationState
                        )
                    }
                }
            }
        )

        return VStack(spacing: 0) {
            SearchField(text: $searchModel.searchText)

            if searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            } else if searchModel.displayedGroups.isEmpty {
                SearchEmptyView()
            } else {
                SearchResultsList(groups: searchModel.displayedGroups) { entry in
                    SettingsSearchNavigation.selectSearchResult(
                        entry,
                        navigationState: navigationState,
                        query: &searchModel.searchText
                    )
                }
            }
        }
        .navigationSplitViewColumnWidth(ideal: 180, max: 220)
    }

    @ViewBuilder
    private var settingsPane: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .general:
            GeneralSettingsPane(
                settings: appState.settings.general,
                advancedSettings: appState.settings.advanced
            )
        case .menuBarLayout:
            MenuBarLayoutSettingsPane(
                itemManager: appState.itemManager,
                advancedSettings: appState.settings.advanced
            )
        case .displays:
            DisplaySettingsPane(displaySettings: appState.settings.displaySettings)
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
        case .triggers:
            TriggersSettingsPane(manager: appState.settings.triggers, itemManager: appState.itemManager)
        case .tools:
            ToolsSettingsPane(settings: appState.settings.advanced)
        case .developer:
            DeveloperSettingsPane(manager: appState.settings.triggers)
        case .about:
            AboutSettingsPane(updatesManager: appState.updatesManager)
        }
    }

    private func navigateBack() {
        guard let index = currentSectionIndex, index > 0 else { return }
        navigationState.settingsNavigationIdentifier = allSections[index - 1]
    }

    private func navigateForward() {
        guard let index = currentSectionIndex, index < allSections.count - 1 else { return }
        navigationState.settingsNavigationIdentifier = allSections[index + 1]
    }
}
