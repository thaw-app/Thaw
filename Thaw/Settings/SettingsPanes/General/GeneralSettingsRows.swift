//
//  GeneralSettingsRows.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import LaunchAtLogin
import SwiftUI

// The handful of general settings that both ``GeneralSettingsPane`` and
// ``SimpleModeSettingsPane`` offer.
//
// These are the settings a user would notice missing, so Simple Mode shows
// them too. Defining each row once keeps the two panes from drifting.
//
// Rows the full pane grows out of these — the hover delay, the rehide
// strategy, the always-hidden gestures — stay in ``GeneralSettingsPane``.
// They are what Simple Mode exists to leave out.

// MARK: - LaunchAtLoginRow

/// Whether the app starts with the user's session.
struct LaunchAtLoginRow: View {
    var body: some View {
        LaunchAtLogin.Toggle {
            Text("Launch at Login")
        }
    }
}

// MARK: - ShowIceIconRow

/// Whether the app's own menu bar icon is shown, and which icon it is.
struct ShowIceIconRow: View {
    @Bindable var settings: GeneralSettings

    var body: some View {
        Toggle("Show \(Constants.displayName) icon", isOn: $settings.showIceIcon)
            .annotation("Show the \(Constants.displayName) icon in the menu bar. Click to show hidden items, double-click for always-hidden, and right-click for settings.")
        if settings.showIceIcon {
            IceIconPicker(settings: settings)
        }
    }
}

// MARK: - ShowHiddenItemsOnRow

/// Which gestures on an empty stretch of the menu bar reveal hidden items.
///
/// All three fit on one row as a button group, so Simple Mode takes the whole
/// control rather than a two-gesture variant of it. A user who never finds
/// this row thinks the app is broken, which is what earns it a place there.
struct ShowHiddenItemsOnRow: View {
    @Bindable var settings: GeneralSettings

    var body: some View {
        LabeledContent("Show hidden items on") {
            ControlGroup {
                Toggle("Click", isOn: $settings.showOnClick)
                    .help("Click an empty area of the menu bar to show hidden menu bar items.")
                Toggle("Hover", isOn: $settings.showOnHover)
                    .help("Hover over an empty area of the menu bar to show hidden menu bar items.")
                Toggle("Scroll", isOn: $settings.showOnScroll)
                    .help("Scroll or swipe in the menu bar to show hidden menu bar items.")
            }
            .toggleStyle(.button)
            .fixedSize()
        }
        .annotation("Show hidden menu bar items by clicking, hovering, or scrolling in an empty area of the menu bar.")
    }
}

// MARK: - AutoRehideRow

/// Whether revealed items hide themselves again.
struct AutoRehideRow: View {
    @Bindable var settings: GeneralSettings

    var body: some View {
        Toggle("Automatically rehide", isOn: $settings.autoRehide)
    }
}
