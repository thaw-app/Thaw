//
//  SettingsViewComponents.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - SettingsOverflowMenu

/// The toolbar's overflow menu: window-level switches that have no pane of their own.
/// Anything with a row in a pane stays out, so each setting has one home.
struct SettingsOverflowMenu: View {
    let appState: AppState
    let generalSettings: GeneralSettings

    var body: some View {
        @Bindable var generalSettings = generalSettings
        let menuBarManager = appState.menuBarManager
        Menu {
            Button(menuBarManager.isSwapped ? "Swap Back" : "Swap Shown and Hidden Items") {
                menuBarManager.toggleSwap()
            }
            Button(menuBarManager.isZenModeActive ? "Leave Zen Mode" : "Zen Mode") {
                menuBarManager.toggleZenMode()
            }
            Divider()
            Menu {
                AppUIZoomControls(strings: .thaw, showsShortcuts: false)
            } label: {
                Text("Zoom")
            }
            Divider()
            Toggle("Simple Mode", isOn: $generalSettings.simpleMode)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .help("More")
    }
}

// MARK: - SettingsSearchResults

/// Search results in the detail column, on the same reading width as the
/// panes they stand in for.
struct SettingsSearchResults: View {
    @Environment(SearchModel.self) private var searchModel
    let navigationState: AppNavigationState

    private var resultCount: Int {
        searchModel.displayedGroups.reduce(0) { $0 + $1.entries.count }
    }

    var body: some View {
        @Bindable var searchModel = searchModel
        if searchModel.displayedGroups.isEmpty {
            SearchEmptyView(query: searchModel.searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // A count makes a long list read as bounded, and tells the
                // reader whether narrowing the query is worth it.
                SettingsSearchResultCount(Text("^[\(resultCount) result](inflect: true)"))
                    .padding(.top, ThawSpacing.inset)
                    .padding(.horizontal, SettingsDetailLayout.titleHorizontalInset + 6)
                    .padding(.bottom, ThawSpacing.compact)

                SearchResultsList(groups: searchModel.displayedGroups) { entry in
                    SettingsSearchNavigation.selectSearchResult(
                        entry,
                        navigationState: navigationState,
                        query: &searchModel.searchText
                    )
                }
                .frame(maxWidth: SettingsDetailLayout.columnMaxWidth)
                .padding(.horizontal, SettingsDetailLayout.titleHorizontalInset - 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - SettingsSidebar

/// The sidebar column: the list of pages, at Floe's width.
///
/// The pane header names the pane; the sidebar only lists where to go.
struct SettingsSidebar: View {
    @Environment(SearchModel.self) private var searchModel
    let appState: AppState
    let navigationState: AppNavigationState
    let generalSettings: GeneralSettings

    var body: some View {
        SettingsSidebarPaneList(
            navigationState: navigationState,
            turnedOff: SettingsSidebarPanes.panesTurnedOff(
                isEnabled: appState.moduleHost.isEnabled,
                profilesOn: appState.profilesFeature.isOn
            )
        )
        .onChange(of: generalSettings.simpleMode) { _, _ in
            searchModel.updateDisplayedItems()
        }
    }
}

// MARK: - SettingsPaneHistory

/// Back and forward through the panes visited in this window, like a
/// browser, so a detour to check one setting is one click back.
@MainActor
@Observable
final class SettingsPaneHistory {
    private(set) var back: [SettingsNavigationIdentifier] = []
    private(set) var forward: [SettingsNavigationIdentifier] = []
    /// Set while a history move is changing the pane, so the change is not
    /// recorded as a new visit.
    private var isTravelling = false

    func record(leaving pane: SettingsNavigationIdentifier) {
        guard !isTravelling else { return }
        back.append(pane)
        if back.count > 50 {
            back.removeFirst()
        }
        forward.removeAll()
    }

    func goBack(from current: SettingsNavigationIdentifier, navigationState: AppNavigationState) {
        guard let target = back.popLast() else { return }
        forward.append(current)
        travel(to: target, navigationState: navigationState)
    }

    func goForward(from current: SettingsNavigationIdentifier, navigationState: AppNavigationState) {
        guard let target = forward.popLast() else { return }
        back.append(current)
        travel(to: target, navigationState: navigationState)
    }

    private func travel(to pane: SettingsNavigationIdentifier, navigationState: AppNavigationState) {
        isTravelling = true
        SettingsSearchNavigation.selectSidebarPane(pane, navigationState: navigationState)
        isTravelling = false
    }
}

struct SettingsHistoryButtons: View {
    let history: SettingsPaneHistory
    let navigationState: AppNavigationState

    var body: some View {
        HStack(spacing: ThawSpacing.tight) {
            Button {
                history.goBack(from: navigationState.settingsNavigationIdentifier, navigationState: navigationState)
            } label: {
                Label("Back", systemImage: "chevron.backward")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(history.back.isEmpty)
            .help("Back")

            Button {
                history.goForward(from: navigationState.settingsNavigationIdentifier, navigationState: navigationState)
            } label: {
                Label("Forward", systemImage: "chevron.forward")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(history.forward.isEmpty)
            .help("Forward")
        }
    }
}
