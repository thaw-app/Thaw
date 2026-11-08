//
//  ThawBarSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The Thaw Bar page: per-display fields, where a shortcut opens the bar, and the app-wide options.
///
/// Spacing and the template for new displays live on the Displays pane, which owns the relaunch-guarded apply.
struct ThawBarSettingsPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var displaySettings: DisplaySettingsManager

    /// The display the controls below edit. Nil until the page first appears,
    /// and whenever the chosen display drops out of the known displays.
    @State private var selectedDisplayUUID: String?

    @State private var tab = ThawBarTab.display

    var body: some View {
        ThawForm {
            ThawSection {
                Text("Preview")
            } content: {
                let configuration = displaySettings.configuration(for: previewTarget)
                ThawBarPreview(
                    itemManager: appState.itemManager,
                    layout: configuration.thawBarLayout,
                    gridColumns: configuration.gridColumns,
                    useThawBar: configuration.useThawBar,
                    displayID: previewDisplayID,
                    itemSpacingOffset: configuration.itemSpacingOffset,
                    itemScale: configuration.thawBarItemScale
                )
            }

            SettingsPaneTabs(
                selection: $tab,
                tabs: ThawBarTab.allCases,
                tabForSection: ThawBarTab.init(section:)
            )

            switch tab {
            case .display:
                displayPicker
                if let uuid = editedDisplayUUID {
                    configurationControls(for: uuid)
                }
            case .look:
                // The look sits under the preview it changes; it applies on every display.
                ThawBarAppearanceEditor(configuration: Bindable(appState.appearanceManager).configuration)
            case .allDisplays:
                ThawSection("Options for all displays") {
                    appWideOptions
                }
            }
        }
        .onAppear {
            // Open on the first connected display, so the page shows something the user can act on.
            if selectedDisplayUUID == nil {
                selectedDisplayUUID = displaySettings.displays.first(where: { $0.isConnected })?.id
            }
        }
    }

    // MARK: - Display choice

    /// The chosen display, or the first known one when the choice is unset or no longer known.
    private var editedDisplayUUID: String? {
        let displays = displaySettings.displays
        if let selectedDisplayUUID, displays.contains(where: { $0.id == selectedDisplayUUID }) {
            return selectedDisplayUUID
        }
        return displays.first?.id
    }

    /// With no display known yet, the preview shows the template new displays start from.
    private var previewTarget: DisplaySettingsManager.ConfigurationTarget {
        editedDisplayUUID.map { .display($0) } ?? .template
    }

    /// The display ID for the previewed display when it is connected; nil otherwise.
    private var previewDisplayID: CGDirectDisplayID? {
        displaySettings.displays.first { $0.id == editedDisplayUUID && $0.isConnected }?.displayID
    }

    /// Which display the controls below edit.
    @ViewBuilder
    private var displayPicker: some View {
        let displays = displaySettings.displays

        ThawSection {
            Text("Applies to")
        } content: {
            if displays.isEmpty {
                Text("No displays are known yet. Settings for new displays are in Displays, under Template.")
                    .font(.callout)
                    .foregroundStyle(ThawInk.supporting)
            } else {
                ThawPicker(selection: Binding(
                    get: { editedDisplayUUID ?? displays[0].id },
                    set: { selectedDisplayUUID = $0 }
                )) {
                    ForEach(displays) { display in
                        Text(verbatim: display.name).tag(display.id)
                    }
                } label: {
                    Text("Display")
                }
                .annotation { displayAnnotation }
            }
        }
    }

    @ViewBuilder
    private var displayAnnotation: some View {
        if let display = displaySettings.displays.first(where: { $0.id == editedDisplayUUID }),
           !display.isConnected
        {
            Text("\(display.name) is disconnected. You can still edit its saved configuration; it applies when this display reconnects.")
        }
    }

    // MARK: - Per-display controls

    private func configurationControls(for uuid: String) -> some View {
        let target = DisplaySettingsManager.ConfigurationTarget.display(uuid)
        return ThawSection {
            Text("Behavior")
        } content: {
            ThawBarConfigurationControls(
                alwaysShowHiddenItems: displaySettings.binding(for: target, \.alwaysShowHiddenItems) { $0.withAlwaysShowHiddenItems($1) },
                useThawBar: displaySettings.binding(for: target, \.useThawBar) { $0.withUseThawBar($1) },
                location: displaySettings.binding(for: target, \.thawBarLocation) { $0.withThawBarLocation($1) },
                layout: displaySettings.binding(for: target, \.thawBarLayout) { $0.withThawBarLayout($1) },
                gridColumns: displaySettings.binding(for: target, \.gridColumns) { $0.withGridColumns($1) },
                itemScale: displaySettings.binding(for: target, \.thawBarItemScale) { $0.withThawBarItemScale($1) },
                shortcutPlacement: Binding(
                    get: { ThawBarShortcutPlacement(opensAtPointer: appState.settings.thawBar.thawBarLocationOnHotkey) },
                    set: { appState.settings.thawBar.thawBarLocationOnHotkey = $0.opensAtPointer }
                ),
                context: .display
            ) {
                // Only matters while the bar is off here and Always Hidden is on.
                if !displaySettings.configuration(forUUID: uuid).useThawBar,
                   appState.settings.layout.isAlwaysHiddenSectionEnabled
                {
                    Toggle(
                        "Open Always Hidden in the \(Constants.displayName) Bar",
                        isOn: displaySettings.binding(for: target, \.useThawBarForAlwaysHidden) { $0.withUseThawBarForAlwaysHidden($1) }
                    )
                    .annotation("Hidden items still show in the menu bar. Showing Always Hidden there would open Hidden too.")
                }
            }
        }
    }

    // MARK: - App-wide options

    /// The app-wide toggles: position lock and where clicked items open.
    @ViewBuilder
    private var appWideOptions: some View {
        Toggle(
            "Lock \(Constants.displayName) Bar position",
            isOn: Binding(
                get: { appState.settings.thawBar.lockThawBarPosition },
                set: { appState.settings.thawBar.lockThawBarPosition = $0 }
            )
        )
        .annotation("Keeps the \(Constants.displayName) Bar where it opens. Turn off to drag it by its background; it opens in its usual place again next time.")

        Toggle(
            "Show clicked items in the menu bar",
            isOn: Binding(
                get: { appState.settings.thawBar.openHiddenItemsInMenuBar },
                set: { appState.settings.thawBar.openHiddenItemsInMenuBar = $0 }
            )
        )
        .annotation("When you open a hidden item from the \(Constants.displayName) Bar or search, \(Constants.displayName) shows it in the menu bar and opens its menu under its icon. Turn off to open the menu without showing the item.")

        Toggle(
            "Open items the notch pushes out in the Thaw Bar",
            isOn: Binding(
                get: { appState.settings.thawBar.useThawBarOnNotchOverflow },
                set: { appState.settings.thawBar.useThawBarOnNotchOverflow = $0 }
            )
        )
        .annotation("When items don't fit beside the notch, the \(Constants.displayName) Bar shows the ones macOS pushed out. Turn off to reveal inline only; pushed-out items stay hidden until there's room.")
    }
}

nonisolated enum ThawBarTab: CaseIterable, ThawTab {
    case display
    case look
    case allDisplays

    /// The tab holding a search result's section.
    init?(section: String) {
        guard section == "Options for all displays" else { return nil }
        self = .allDisplays
    }

    var title: LocalizedStringResource {
        switch self {
        case .display: "Display"
        case .look: "Look"
        case .allDisplays: "All Displays"
        }
    }

    var systemImage: String {
        switch self {
        case .display: "display"
        case .look: "paintbrush"
        case .allDisplays: "rectangle.on.rectangle"
        }
    }
}
