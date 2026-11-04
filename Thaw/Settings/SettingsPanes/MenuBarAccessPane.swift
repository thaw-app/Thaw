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
    @Bindable var settings: GeneralSettings
    @Bindable var advancedSettings: AdvancedSettings

    var body: some View {
        ThawForm {
            ThawSection("Reveal hidden items") {
                ShowHiddenItemsOnRow(settings: settings)
                alwaysHiddenGestures
            }
            .thawAnimation(ThawMotion.settle, value: advancedSettings.isAlwaysHiddenSectionEnabled)

            ThawSection("After revealing") {
                AutoRehideRow(settings: settings)
                    .annotation("Hidden items go away again when you click elsewhere or switch apps.")
                tempShowIntervalRow
            }

            ThawSection("Zen Mode") {
                ZenModeWhileRow(settings: advancedSettings)
            }

            ThawSection("Swap shown and hidden") {
                swapBarToggle
            }

            ThawSection("Menu bar search") {
                searchPresentationPicker
            }

            ThawSection("On hover") {
                HoverReadoutsRow(settings: advancedSettings)
            }
        }
        .sliderLabelAlignment()
    }

    // MARK: - Swap

    /// The Swap Bar makes swapping one click; the note names the other ways so the toggle doesn't read as the only one.
    private var swapBarToggle: some View {
        Toggle("Show Swap Bar", isOn: $advancedSettings.enableSwapBar)
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
            "Hide again after",
            value: $settings.tempShowInterval,
            in: 0 ... 30,
            step: 1
        )
        .annotation("How long a hidden menu bar item you open from search or the Thaw Bar stays in the menu bar.")
    }

    // MARK: - Always Hidden gestures

    @ViewBuilder
    private var alwaysHiddenGestures: some View {
        if advancedSettings.isAlwaysHiddenSectionEnabled {
            // A sentence, not a labelled value: nothing here can be changed.
            Text("Double-click or Option-click an empty area of the menu bar or the \(Constants.displayName) icon to show Always Hidden menu bar items.")
                .foregroundStyle(ThawInk.supporting)
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
        ThawPicker("Where the panel opens", selection: $advancedSettings.menuBarSearchPresentation) {
            ForEach(SearchPresentation.allCases) { presentation in
                Text(presentation.localized).tag(presentation)
            }
        }
        .annotation {
            Text(searchPresentationExplanation)
        }
    }

    private var searchPresentationExplanation: LocalizedStringKey {
        switch advancedSettings.menuBarSearchPresentation {
        case .inspector:
            """
            The panel opens in the spot you last dragged it to, one per display, \
            listing every item by section.
            """
        case .launcher:
            """
            The panel opens in the middle of the screen, the way Spotlight does, \
            showing the items you used recently until you start typing.
            """
        case .assisted:
            """
            The panel opens next to the pointer with large rows and large type, \
            listing every item, so you can pick one by reading and clicking \
            instead of aiming at the menu bar.
            """
        }
    }
}
