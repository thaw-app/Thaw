//
//  MenuBarAccessPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The Visibility pane: revealing and rehiding, Zen Mode, the Swap Bar, search and hover.
struct MenuBarAccessPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: VisibilitySettings
    @AppStorage(Defaults.Key.showSearchShortcutBar.rawValue) private var showSearchShortcutBar = Defaults.DefaultValue.showSearchShortcutBar
    @AppStorage(Defaults.Key.rememberSearchQuery.rawValue) private var rememberSearchQuery = Defaults.DefaultValue.rememberSearchQuery

    var body: some View {
        ThawForm {
            ThawSection("Reveal hidden items") {
                ShowHiddenItemsOnRow(settings: settings)
                HoverDelayRow(settings: settings)
                alwaysHiddenGestures
            }
            .thawAnimation(ThawMotion.settle, value: appState.settings.layout.isAlwaysHiddenSectionEnabled)

            ThawSection("After revealing") {
                RehideChoiceRow(settings: settings)
                RehideDelayRow(settings: settings)
                tempShowIntervalRow
            }

            ThawSection("Zen Mode") {
                ZenModeWhileRow(settings: settings)
                RecordingAlertRows(settings: settings)
            }

            ThawSection("Swap shown and hidden") {
                swapBarToggle
                SwapOnIconClickToggle(settings: settings)
            }

            ThawSection("Menu bar search") {
                searchPresentationPicker
                Toggle("Show shortcut bar", isOn: $showSearchShortcutBar)
                    .settingsSearchAnchor("general.showSearchShortcutBar")
                    .annotation("The bar under the results with Settings, Rename, Actions and their keyboard shortcuts. The shortcuts work either way.")
                Toggle("Remember last search", isOn: $rememberSearchQuery)
                    .settingsSearchAnchor("general.rememberSearchQuery")
                    .annotation("Open search with the text you last typed.")
            }

            ThawSection("On hover") {
                HoverReadoutsRow(settings: settings)
                TooltipDelayRow(settings: settings)
            }
        }
        .sliderLabelAlignment()
    }

    // MARK: - Swap

    /// The Swap Bar makes swapping one click; the note names the other ways so the toggle doesn't read as the only one.
    private var swapBarToggle: some View {
        Toggle("Show Swap Bar", isOn: $settings.enableSwapBar)
            .settingsSearchAnchor("advanced.enableSwapBar")
            .annotation(
                "A strip under the menu bar that trades your shown and hidden items in one click.",
                more: """
                The hidden items move onto the menu bar and the shown ones move off, each group \
                in its own order. It's a real layout change, so it lasts through a relaunch until \
                you swap back. The Swap Bar also holds the active profile, the section toggles \
                and Zen Mode, and never takes focus from your app. Without it, swap with a \
                keyboard shortcut, a Shortcuts action, or the More menu in Settings.
                """
            )
    }

    // MARK: - Rehide

    private var tempShowIntervalRow: some View {
        SecondsSliderRow(
            "Keep opened items in the menu bar for",
            value: $settings.tempShowInterval,
            in: 0 ... 30,
            step: 1
        )
        .settingsSearchAnchor("general.tempShowInterval")
        .annotation("How long a hidden menu bar item you open from search or the Thaw Bar stays in the menu bar before it hides again.")
    }

    // MARK: - Always Hidden gestures

    @ViewBuilder
    private var alwaysHiddenGestures: some View {
        if appState.settings.layout.isAlwaysHiddenSectionEnabled {
            Toggle("Double-click the \(Constants.displayName) icon to show Always Hidden", isOn: $settings.showAlwaysHiddenOnIconDoubleClick)
                .settingsSearchAnchor("advanced.showAlwaysHiddenOnIconDoubleClick")
                .annotation("Option-click and gestures in empty menu bar space are unchanged.")
        } else {
            LabeledContent("Always Hidden is off") {
                Button("Open Layout") {
                    SettingsSearchNavigation.selectSidebarPane(
                        .menuBarLayout,
                        navigationState: appState.navigationState
                    )
                }
                .buttonStyle(.settingsGlass)
            }
            .annotation("Turn on Always Hidden in Layout to use it.")
        }
    }

    // MARK: - Search

    private var searchPresentationPicker: some View {
        ThawPicker("Panel layout", selection: $settings.menuBarSearchPresentation) {
            ForEach(SearchPresentation.allCases) { presentation in
                Text(presentation.localized).tag(presentation)
            }
        }
        .settingsSearchAnchor("general.menuBarSearchPresentation")
        .annotation {
            Text(settings.menuBarSearchPresentation.summary)
        }
    }
}
