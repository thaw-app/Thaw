//
//  MenuBarAccessPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawCapture
import ThawUI

/// The "Behavior" surface of the Menu Bar destination: the shared
/// reveal/rehide behavior, search presentation and menu bar tooltips.
///
/// Thaw Bar configuration (placement, layout, grid) lives on the Thaw Bar
/// page, which this links to. Menu bar item spacing and the whole-template
/// broadcast stay on the Displays pane, which owns the relaunch-guarded
/// apply flow.
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

            ThawSection("When an icon changes") {
                AlertRevealItemList()
            }

            ThawSection("Swap shown and hidden") {
                swapBarToggle
            }

            ThawSection("Menu bar search") {
                searchPresentationPicker
            }

            ThawSection("Tooltips") {
                if ScreenCapture.hasCachedScreenRecordingPermission {
                    showMenuBarTooltips
                } else {
                    SettingsWarningPill(
                        title: "Tooltips need Screen Recording",
                        message: "Turn it on to see an item's name when you hover over it.",
                        systemImage: "eye.slash",
                        actionTitle: "Grant Access",
                        action: { appState.permissions.screenRecording.performRequest() }
                    )
                }
            }
        }
        .sliderLabelAlignment()
    }

    // MARK: - Swap

    /// The swap is the reason the two groups exist: trade them and the bar
    /// carries the other group, without ever holding both. The bar is the
    /// surface that makes it one click; the keyboard shortcut and the Shortcuts action
    /// are the other two ways in, named here so the toggle does not read as
    /// the only one.
    private var swapBarToggle: some View {
        Toggle("Show Swap Bar", isOn: $advancedSettings.enableSwapBar)
            .annotation(
                "A strip under the menu bar that trades your shown and hidden items in one click.",
                more: """
                Swap moves the hidden items onto the menu bar and the shown ones off, each group \
                in its own order, until you swap back. It is a real layout change, so it stays \
                that way through a relaunch. The Swap Bar sits under the menu bar on the display \
                your pointer is on, beside the active profile, the section toggles, and Zen Mode, \
                and never takes focus from the app you are in. Right-click the menu bar, a \
                keyboard shortcut, or a Shortcuts action reach the same swap without it.
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

    // MARK: - Tooltips

    private var showMenuBarTooltips: some View {
        Toggle("Show tooltips in the menu bar", isOn: $advancedSettings.showMenuBarTooltips)
            .annotation("Show a tooltip when hovering over menu bar items in the actual menu bar.")
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
