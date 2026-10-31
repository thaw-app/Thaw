//
//  SettingsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppUIZoom.defaultsKey) private var zoomPercent = 100

    let appState: AppState
    let navigationState: AppNavigationState
    let generalSettings: GeneralSettings
    @State private var settingsWindow: NSWindow?

    /// Shared settings search state, driving the detail header's search field
    /// the single search entry point. The sidebar is navigation only, so
    /// results take over the detail column rather than the pane list.
    @State private var searchModel = SearchModel()
    @State private var paneHistory = SettingsPaneHistory()

    private var isSearching: Bool {
        !searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if generalSettings.simpleMode {
                // No sidebar at all: one screen is the whole point of Simple
                // Mode, and a sidebar listing a single item is just a sidebar.
                simpleModeScreen
            } else {
                fullSettingsScreen
            }
        }
        // Applied here rather than on the Scene so it can follow the mode: with
        // .windowResizability(.contentSize) this minimum is the window's, and
        // the full layout's would otherwise hold Simple Mode open at a sidebar's
        // width forever.
        .frame(
            minWidth: SettingsWindowMetrics.minimum(simpleMode: generalSettings.simpleMode).width / zoomScale,
            minHeight: SettingsWindowMetrics.minimum(simpleMode: generalSettings.simpleMode).height / zoomScale
        )
        .environment(\.settingsDescriptionsVisible, generalSettings.showSettingDescriptions)
        .settingsWindowBackground(SettingsWindowBackground(isBlack: generalSettings.blackSettingsBackground))
        .environment(searchModel)
        // Both layouts title the toolbar themselves: the full one with the
        // pane, Simple Mode with the app and the mode. Cleared here so the
        // window never falls back to the scene's title.
        .navigationTitle("")
        .onWindowChange { window in
            settingsWindow = window
            if let window {
                appState.settingsProcessHost.appWindowOpened(window)
                SettingsWindowDiagnostics.logWhenLaidOut(
                    window, zoomPercent: zoomPercent, isSimpleMode: generalSettings.simpleMode
                )
            }
        }
        .onChange(of: generalSettings.simpleMode) { _, isSimpleMode in
            resizeSettingsWindow(forSimpleMode: isSimpleMode)
            // Simple Mode's folded bar draws captured glyphs where the full
            // window's General pane draws none, so the mode switch decides
            // whether capture is on.
            navigationState.isSimpleModeSettings = isSimpleMode
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var zoomScale: CGFloat {
        CGFloat(AppUIZoom.normalized(zoomPercent)) / 100
    }

    private var simpleModeScreen: some View {
        // No sidebar and no navigation: one scrolling page is the whole point
        // of Simple Mode. The title bar names the mode, so the page has no
        // heading of its own and opens straight on the folded bar; arranging
        // comes first, app plumbing last.
        SimpleModeSettingsPane(
            itemManager: appState.itemManager,
            updatesManager: appState.updatesManager,
            settings: generalSettings
        )
        .environment(\.settingsPaneTitle, nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("\(Constants.displayName): Simple Mode")
        // The same overflow menu as the full window, so the mode switch sits
        // in the same place whichever way the window is showing.
        .toolbar {
            // A labelled way out, so leaving Simple Mode doesn't depend on finding the overflow menu.
            ToolbarItem(placement: .primaryAction) {
                Button("All Settings") {
                    generalSettings.simpleMode = false
                }
                .help("Leave Simple Mode and show every settings page")
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsOverflowMenu(appState: appState, generalSettings: generalSettings)
            }
        }
    }

    private var fullSettingsScreen: some View {
        @Bindable var searchModel = searchModel
        // The system toolbar is the pane header. It stays put while the form scrolls and blurs under it, and carries
        // the search field and the overflow menu on its trailing edge.
        return ThawSettingsShell(title: Text(toolbarTitle), subtitle: toolbarSubtitle, sidebarMaxWidth: 250) {
            sidebar
        } detail: {
            detailContent
                .onChange(of: navigationState.settingsNavigationIdentifier) { previous, _ in
                    paneHistory.record(leaving: previous)
                }
                .background {
                    // History's shortcuts live in the content, not on the
                    // toolbar buttons: a toolbar item that carries a
                    // keyboardShortcut is vended with focused values every
                    // layout pass, and AppKit refuses the 406th constraints pass.
                    Button("Back") {
                        paneHistory.goBack(from: navigationState.settingsNavigationIdentifier, navigationState: navigationState)
                    }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(paneHistory.back.isEmpty)
                    .hidden()
                    Button("Forward") {
                        paneHistory.goForward(from: navigationState.settingsNavigationIdentifier, navigationState: navigationState)
                    }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(paneHistory.forward.isEmpty)
                    .hidden()
                }
        } toolbar: {
            // History on the leading edge, the overflow menu beside search.
            ToolbarItemGroup(placement: .navigation) {
                SettingsHistoryButtons(history: paneHistory, navigationState: navigationState)
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsOverflowMenu(appState: appState, generalSettings: generalSettings)
            }
        }
        .settingsSearchField(
            text: $searchModel.searchText,
            placement: .toolbar,
            prompt: "Search",
            findLabel: "Find"
        )
    }

    private var toolbarTitle: LocalizedStringResource {
        isSearching ? "Search" : navigationState.settingsNavigationIdentifier.localized
    }

    private var toolbarSubtitle: Text {
        isSearching ? Text(verbatim: "") : Text(navigationState.settingsNavigationIdentifier.subtitle)
    }

    @ViewBuilder
    private var detailContent: some View {
        if isSearching {
            SettingsSearchResults(navigationState: navigationState)
                .id("search")
                .transition(paneTransition)
        } else {
            settingsPane
                .id(navigationState.settingsNavigationIdentifier)
                .transition(paneTransition)
                // The toolbar names the pane; the pane's own title slot stays
                // empty so nothing prints it twice.
                .environment(\.settingsPaneTitle, nil)
        }
    }

    private var paneTransition: AnyTransition {
        // Insertion-only: cross-fading two full panes doubles the glass and
        // material layers WindowServer composites for the whole fade, which
        // reads as pane-switch lag. Removing the old pane instantly keeps at
        // most one pane's worth of glass on screen.
        reduceMotion
            ? .identity
            : .asymmetric(
                insertion: .opacity.animation(ThawMotion.pane),
                removal: .identity
            )
    }

    /// Brings the window to the size the incoming layout wants.
    ///
    /// The minimum alone cannot do this: it lets Simple Mode be shrunk, it does
    /// not shrink anything, so switching modes would leave the old layout's
    /// frame with the new layout rattling around inside it. Only shrinks on the
    /// way in and grows on the way out, so a window someone has already sized to
    /// taste within a mode is left alone. Anchored at the top-left because
    /// AppKit sizes from the bottom.
    private func resizeSettingsWindow(forSimpleMode isSimpleMode: Bool) {
        guard let window = settingsWindow else {
            return
        }
        let preferred = SettingsWindowMetrics.preferred(simpleMode: isSimpleMode)
        let current = window.frame.size
        let target = CGSize(
            width: isSimpleMode ? min(current.width, preferred.width) : max(current.width, preferred.width),
            height: isSimpleMode ? min(current.height, preferred.height) : max(current.height, preferred.height)
        )
        guard target != current else {
            return
        }
        let origin = window.frame.origin
        window.setFrame(
            NSRect(
                x: origin.x,
                y: origin.y + (current.height - target.height),
                width: target.width,
                height: target.height
            ),
            display: true,
            // Never the blocking animate: true loop: it re-displays every
            // frame on the main thread while SwiftUI is simultaneously
            // swapping the entire mode tree, which is the Simple Mode
            // transition lag. One instant resize under the mode swap reads
            // faster than a stuttering animation.
            animate: false
        )
    }

    // No window-chrome or surface overrides here on purpose: the sidebar keeps
    // AppKit's own source-list material and the detail column its window
    // background, which is what a stock settings window looks like.

    private var sidebar: some View {
        SettingsSidebar(
            appState: appState,
            navigationState: navigationState,
            generalSettings: appState.settings.general
        )
    }

    @ViewBuilder
    private var settingsPane: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .menuBarLayout:
            MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
        case .visibility:
            MenuBarAccessPane(
                settings: appState.settings.general,
                advancedSettings: appState.settings.advanced
            )
        case .thawBar:
            ThawBarSettingsPane(displaySettings: appState.settings.displaySettings)
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane(appearanceManager: appState.appearanceManager)
        case .widgets:
            WidgetsSettingsPane(settings: appState.settings.advanced)
        case .profiles:
            ProfileSettingsPane(profileManager: appState.profileManager)
        case .hotkeys:
            HotkeysSettingsPane(settings: appState.settings.hotkeys)
        case .automation, .triggers:
            TriggersSettingsPane()
        case .displays, .spaces:
            DisplaySettingsPane(displaySettings: appState.settings.displaySettings)
        case .general, .theLab:
            GeneralSettingsPane(
                settings: appState.settings.general,
                advancedSettings: appState.settings.advanced
            )
        case .privacy:
            PrivacySettingsPane(
                updatesManager: appState.updatesManager,
                advancedSettings: appState.settings.advanced
            )
        case .tools:
            ToolsSettingsPane(settings: appState.settings.advanced)
        case .modules:
            ModulesSettingsPane(moduleHost: appState.moduleHost, profiles: appState.profilesFeature)
        case .about:
            ThawAboutPane(updatesManager: appState.updatesManager)
        case .scripts:
            ScriptsSettingsPane()
        case .advanced:
            // Advanced was dissolved, so a saved pane that names it opens Layout.
            MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
        }
    }
}

// MARK: - SettingsDetailHeader

/// The toolbar's overflow menu: window-level switches that have no pane of their own.
/// Anything with a row in a pane stays out, so each setting has one home.
private struct SettingsOverflowMenu: View {
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
        }
        .menuIndicator(.hidden)
    }
}

// MARK: - SettingsSearchResults

/// Search results in the detail column, on the same reading width as the
/// panes they stand in for.
private struct SettingsSearchResults: View {
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
                Text("^[\(resultCount) result](inflect: true)")
                    .font(ThawType.detail.weight(.medium))
                    .foregroundStyle(ThawInk.supporting)
                    .padding(.horizontal, SettingsDetailLayout.titleHorizontalInset + 6)
                    .padding(.bottom, ThawSpacing.compact)
                    .accessibilityAddTraits(.updatesFrequently)

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
private struct SettingsSidebar: View {
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

// MARK: - Toolbar pieces

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

private struct SettingsHistoryButtons: View {
    let history: SettingsPaneHistory
    let navigationState: AppNavigationState

    var body: some View {
        Button {
            history.goBack(from: navigationState.settingsNavigationIdentifier, navigationState: navigationState)
        } label: {
            Label("Back", systemImage: "chevron.backward")
        }
        .disabled(history.back.isEmpty)
        .help("Back")

        Button {
            history.goForward(from: navigationState.settingsNavigationIdentifier, navigationState: navigationState)
        } label: {
            Label("Forward", systemImage: "chevron.forward")
        }
        .disabled(history.forward.isEmpty)
        .help("Forward")
    }
}
