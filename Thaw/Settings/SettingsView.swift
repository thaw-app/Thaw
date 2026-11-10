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

private final class WeakWindowBox {
    weak var window: NSWindow?
}

struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppUIZoom.defaultsKey) private var zoomPercent = 100

    let appState: AppState
    let navigationState: AppNavigationState
    let generalSettings: GeneralSettings
    @State private var settingsWindowBox = WeakWindowBox()

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
        // .windowResizability(.contentMinSize) this minimum is the window's, and
        // the full layout's would otherwise hold Simple Mode open at a sidebar's
        // width forever.
        .frame(
            minWidth: SettingsWindowMetrics.minimum(simpleMode: generalSettings.simpleMode).width / zoomScale,
            minHeight: SettingsWindowMetrics.minimum(simpleMode: generalSettings.simpleMode).height / zoomScale
        )
        .environment(\.settingsDescriptionsVisible, generalSettings.showSettingDescriptions)
        .settingsTheme(generalSettings.settingsAppearance, drawsBackground: true)
        .environment(searchModel)
        .onWindowChange { window in
            settingsWindowBox.window = window
            if let window {
                appState.settingsProcessHost.appWindowOpened(window)
                SettingsWindowDiagnostics.logWhenLaidOut(
                    window, zoomPercent: zoomPercent, isSimpleMode: generalSettings.simpleMode
                )
            }
        }
        .onDisappear {
            settingsWindowBox.window = nil
            searchModel.searchText = ""
            searchModel.clearIndex()
        }
        .onChange(of: generalSettings.simpleMode) { _, isSimpleMode in
            resizeSettingsWindow(forSimpleMode: isSimpleMode)
            // Simple Mode's folded bar draws captured glyphs where the full
            // window's General pane draws none, so the mode switch decides
            // whether capture is on.
            navigationState.isSimpleModeSettings = isSimpleMode
        }
        .disablesAnimations(when: reduceMotion)
    }

    private var zoomScale: CGFloat {
        CGFloat(AppUIZoom.normalized(zoomPercent)) / 100
    }

    private var simpleModeScreen: some View {
        // No sidebar and no navigation: one scrolling page is the whole point
        // of Simple Mode. The header bar names the mode, so the page has no
        // heading of its own and opens straight on the folded bar.
        SettingsSingleHeaderShell(
            title: Text("\(Constants.displayName): Simple Mode")
        ) {
            Button("All Settings") {
                generalSettings.simpleMode = false
            }
            .buttonStyle(.settingsGlass)
            .help("Leave Simple Mode and show every settings page")

            SettingsOverflowMenu(appState: appState, generalSettings: generalSettings)
        } content: {
            SimpleModeSettingsPane(
                itemManager: appState.itemManager,
                updatesManager: appState.updatesManager,
                settings: generalSettings
            )
            .environment(\.settingsPaneTitle, nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var fullSettingsScreen: some View {
        @Bindable var searchModel = searchModel
        return SettingsSplitShell(
            title: Text(toolbarTitle),
            subtitle: isSearching ? nil : Text(navigationState.settingsNavigationIdentifier.subtitle)
        ) {
            sidebar
        } detail: {
            detailContent
                .onChange(of: navigationState.settingsNavigationIdentifier) { previous, _ in
                    paneHistory.record(leaving: previous)
                }
                .background {
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
        } leadingHeader: {
            SettingsHistoryButtons(history: paneHistory, navigationState: navigationState)
        } trailingHeader: {
            SettingsHeaderSearchField(
                text: $searchModel.searchText,
                prompt: "Search",
                findLabel: "Find"
            )
            SettingsOverflowMenu(appState: appState, generalSettings: generalSettings)
        }
    }

    private var toolbarTitle: LocalizedStringResource {
        isSearching ? "Search" : navigationState.settingsNavigationIdentifier.localized
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
        guard let window = settingsWindowBox.window else {
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
