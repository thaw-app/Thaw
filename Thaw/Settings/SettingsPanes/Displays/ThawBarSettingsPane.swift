//
//  ThawBarSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The dedicated Thaw Bar destination: the canonical home for
/// the per-display / template fields ThawBarConfigurationControls edits,
/// plus the app-wide extras (position lock, open-at-pointer-on-hotkey, where
/// hidden items open, Thaw Bar Only).
///
/// Menu bar item spacing stays on the Displays pane (it owns the relaunch-
/// guarded apply flow). Item order, groups, names and shortcuts stay on the
/// Menu Bar editor. Background, shape and icon design are Appearance.
///
/// The editing context is one display or the new-display template
/// (globalConfiguration). A template edit does not broadcast; the Displays
/// pane's "Apply template to all displays" remains the whole-template broadcast.
struct ThawBarSettingsPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var displaySettings: DisplaySettingsManager

    /// What the controls below bind to: a specific display, or the
    /// new-display template. Defaults to the first connected display so the
    /// page opens on something real the user can act on.
    @State private var editingContext: EditingContext = .template

    @State private var isOptionsExpanded = false

    @State private var hasChosenContext = false

    var body: some View {
        ThawForm {
            ThawSection {
                Text("Preview")
            } content: {
                ThawBarPreview(
                    itemManager: appState.itemManager,
                    layout: layoutBindingValue,
                    gridColumns: gridColumnsBindingValue,
                    useThawBar: useThawBarValue,
                    displayID: displayIDValue,
                    itemSpacingOffset: itemSpacingOffsetValue
                )
            }

            contextPicker

            configurationControls(for: editingContext)

            // The look sits beside the preview it changes; it applies on
            // every display.
            ThawBarAppearanceEditor(configuration: Bindable(appState.appearanceManager).configuration)

            DisclosureGroup("Options for all displays", isExpanded: $isOptionsExpanded) {
                appWideOptions
            }
        }
        .onAppear {
            // Default to the first connected display on the first appear, so
            // the page opens on something the user can act on. After that the
            // choice sticks: a user who picked the template keeps it.
            if !hasChosenContext,
               editingContext == .template,
               let first = displaySettings.displays.first(where: { $0.isConnected })
            {
                editingContext = .display(first.id)
            }
            hasChosenContext = true
            if SettingsSearchNavigation.consumeDisclosure(
                .thawBarAppWideOptions,
                navigationState: appState.navigationState
            ) {
                isOptionsExpanded = true
            }
        }
    }

    // MARK: - Editing context

    /// Either a specific display's configuration, or the new-display template.
    private enum EditingContext: Hashable {
        case display(String)
        case template

        private var id: String {
            switch self {
            case let .display(uuid): uuid
            case .template: "__template__"
            }
        }
    }

    /// The scope picker: which display the controls below edit, or the
    /// new-display template.
    @ViewBuilder
    private var contextPicker: some View {
        let displays = displaySettings.displays

        ThawSection {
            Text("Applies to")
        } content: {
            if displays.isEmpty {
                Text("No displays are known yet. Edit the template for new displays instead.")
                    .font(.callout)
                    .foregroundStyle(ThawInk.supporting)
                Button("Edit Template for New Displays") {
                    editingContext = .template
                }
                .buttonStyle(.settingsGlass)
                .disabled(editingContext == .template)
            } else {
                ThawPicker(selection: contextSelectionBinding(displays: displays)) {
                    ForEach(displays) { display in
                        Text(verbatim: display.name).tag(EditingContext.display(display.id))
                    }
                    Divider()
                    Text("Template for new displays").tag(EditingContext.template)
                } label: {
                    Text("Display")
                }
                .annotation { contextAnnotation }
            }
        }
    }

    private func contextSelectionBinding(displays: [DisplaySettingsManager.DisplayInfo]) -> Binding<EditingContext> {
        Binding(
            get: {
                // If the selected context no longer names a known display
                // (it disconnected and dropped out of displays), fall back to
                // the first display so the controls always bind to something.
                switch editingContext {
                case let .display(uuid) where displays.contains(where: { $0.id == uuid }):
                    return editingContext
                case .template:
                    return .template
                default:
                    return .display(displays[0].id)
                }
            },
            set: { editingContext = $0 }
        )
    }

    @ViewBuilder
    private var contextAnnotation: some View {
        switch editingContext {
        case let .display(uuid):
            if let display = displaySettings.displays.first(where: { $0.id == uuid }),
               !display.isConnected
            {
                Text("\(display.name) is disconnected. You can still edit its saved configuration; it applies when this display reconnects.")
            }
        case .template:
            Text("Edits the template applied to displays the next time they connect. Existing displays keep their current settings.")
        }
    }

    // MARK: - Per-context controls

    /// The layout for the current editing context, for the preview.
    private var layoutBindingValue: ThawBarLayout {
        switch editingContext {
        case let .display(uuid): displaySettings.configuration(forUUID: uuid).thawBarLayout
        case .template: displaySettings.globalConfiguration.thawBarLayout
        }
    }

    /// The grid column count for the current editing context, for the preview.
    private var gridColumnsBindingValue: Int {
        switch editingContext {
        case let .display(uuid): displaySettings.configuration(forUUID: uuid).gridColumns
        case .template: displaySettings.globalConfiguration.gridColumns
        }
    }

    /// Whether the Thaw Bar is enabled on the context being previewed.
    private var useThawBarValue: Bool {
        switch editingContext {
        case let .display(uuid): displaySettings.configuration(forUUID: uuid).useThawBar
        case .template: displaySettings.globalConfiguration.useThawBar
        }
    }

    /// The display ID for the context being previewed, when it is a real
    /// connected screen. nil for the template or a disconnected display.
    private var displayIDValue: CGDirectDisplayID? {
        switch editingContext {
        case let .display(uuid):
            displaySettings.displays.first { $0.id == uuid && $0.isConnected }?.displayID
        case .template:
            nil
        }
    }

    /// The item spacing offset saved for the context being previewed.
    private var itemSpacingOffsetValue: Double {
        switch editingContext {
        case let .display(uuid): displaySettings.configuration(forUUID: uuid).itemSpacingOffset
        case .template: displaySettings.globalConfiguration.itemSpacingOffset
        }
    }

    private func configurationControls(for context: EditingContext) -> some View {
        ThawSection {
            Text("Behavior")
        } content: {
            ThawBarConfigurationControls(
                alwaysShowHiddenItems: alwaysShowHiddenItemsBinding(for: context),
                useThawBar: useThawBarBinding(for: context),
                location: locationBinding(for: context),
                layout: layoutBinding(for: context),
                gridColumns: gridColumnsBinding(for: context),
                context: context == .template ? .globalTemplate : .display
            )
        }
    }

    private func useThawBarBinding(for context: EditingContext) -> Binding<Bool> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).useThawBar },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withUseThawBar(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.useThawBar },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withUseThawBar(newValue)
                }
            )
        }
    }

    private func locationBinding(for context: EditingContext) -> Binding<ThawBarLocation> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).thawBarLocation },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withThawBarLocation(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.thawBarLocation },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withThawBarLocation(newValue)
                }
            )
        }
    }

    private func layoutBinding(for context: EditingContext) -> Binding<ThawBarLayout> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).thawBarLayout },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withThawBarLayout(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.thawBarLayout },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withThawBarLayout(newValue)
                }
            )
        }
    }

    private func gridColumnsBinding(for context: EditingContext) -> Binding<Int> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).gridColumns },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withGridColumns(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.gridColumns },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withGridColumns(newValue)
                }
            )
        }
    }

    private func alwaysShowHiddenItemsBinding(for context: EditingContext) -> Binding<Bool> {
        switch context {
        case let .display(uuid):
            return Binding(
                get: { displaySettings.configuration(forUUID: uuid).alwaysShowHiddenItems },
                set: { newValue in
                    displaySettings.updateConfiguration(forDisplayUUID: uuid) { $0.withAlwaysShowHiddenItems(newValue) }
                }
            )
        case .template:
            return Binding(
                get: { displaySettings.globalConfiguration.alwaysShowHiddenItems },
                set: { newValue in
                    displaySettings.globalConfiguration = displaySettings.globalConfiguration.withAlwaysShowHiddenItems(newValue)
                }
            )
        }
    }

    // MARK: - App-wide options

    /// The app-wide toggles: position lock, open-at-pointer-when-summoned-by-
    /// hotkey, where hidden items open, and Thaw Bar Only.
    @ViewBuilder
    private var appWideOptions: some View {
        Toggle(
            "Lock \(Constants.displayName) Bar position",
            isOn: Binding(
                get: { appState.settings.general.lockThawBarPosition },
                set: { appState.settings.general.lockThawBarPosition = $0 }
            )
        )
        .annotation("Keep the \(Constants.displayName) Bar pinned in place. Turn off to move it by dragging its background.")

        Toggle(
            "Show at mouse pointer from a keyboard shortcut",
            isOn: Binding(
                get: { appState.settings.general.thawBarLocationOnHotkey },
                set: { appState.settings.general.thawBarLocationOnHotkey = $0 }
            )
        )
        .annotation("Always show the \(Constants.displayName) Bar at the mouse pointer when a keyboard shortcut opens it.")

        Toggle(
            "Open hidden items in the menu bar",
            isOn: Binding(
                get: { appState.settings.general.openHiddenItemsInMenuBar },
                set: { appState.settings.general.openHiddenItemsInMenuBar = $0 }
            )
        )
        .annotation("Clicking a hidden item shows it in the menu bar and opens its menu under the icon. Turn off to open the menu without showing the icon.")

        // Thaw Bar Only is unplugged for now; restore this with the gate in MenuBarItemManager+ThawBarOnly.swift.
        // Toggle(
        //     "Thaw Bar Only",
        //     isOn: Binding(
        //         get: { appState.settings.general.enableThawBarOnly },
        //         set: { appState.settings.general.enableThawBarOnly = $0 }
        //     )
        // )
        // .annotation("Items macOS won't show in the menu bar stay in the \(Constants.displayName) Bar. Turn this off to treat them as ordinary hidden items. Your list comes back when you turn it on again.")

        // Toggle(
        //     "Menu bar icon for Thaw Bar Only items",
        //     isOn: Binding(
        //         get: { appState.settings.general.showThawBarOnlyLauncher },
        //         set: { appState.settings.general.showThawBarOnlyLauncher = $0 }
        //     )
        // )
        // .annotation("Shows an icon in the menu bar while there are Thaw Bar Only items. Click it to open a small \(Constants.displayName) Bar with just those items.")
        // .disabled(!appState.settings.general.enableThawBarOnly)

        // Toggle(
        //     "Show Thaw Bar Only items when showing hidden items",
        //     isOn: Binding(
        //         get: { appState.settings.general.showThawBarOnlyWithInlineReveal },
        //         set: { appState.settings.general.showThawBarOnlyWithInlineReveal = $0 }
        //     )
        // )
        // .annotation("When you show hidden items, the items kept in the \(Constants.displayName) Bar appear in a small \(Constants.displayName) Bar below the menu bar.")
        // .disabled(!appState.settings.general.enableThawBarOnly)
    }
}
