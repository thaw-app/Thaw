//
//  HoverReadoutsRow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawCapture
import ThawUI

/// What appears while the pointer rests on a menu bar item, as one row: its
/// name in a tooltip, and the details it reports in a readout below it. The
/// name needs Screen Recording, so a note asks for it while it is missing.
struct HoverReadoutsRow: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: AdvancedSettings

    var body: some View {
        ToggleButtonRow("On hover, show") {
            Toggle("Name", isOn: $settings.showMenuBarTooltips)
                .help("A tooltip with the item's name.")
                .disabled(!ScreenCapture.hasCachedScreenRecordingPermission)
            Toggle("Details", isOn: $settings.enableMenuBarItemDescenders)
                .help("A small readout below the item with what it reports, such as a temperature or a count.")
        }
        .annotation(
            "Shows an item's name, or what it reports, while the pointer rests on it in the menu bar.",
            more: "Details are in beta. They show what an item already reports in the space the menu bar has no room for; items that report nothing useful stay as they are."
        )
        if !ScreenCapture.hasCachedScreenRecordingPermission {
            SettingsWarningPill(
                title: "Names need Screen Recording",
                message: "Turn it on to see an item's name when you hover over it.",
                systemImage: "eye.slash",
                actionTitle: "Grant Access",
                action: { appState.permissions.screenRecording.performRequest() }
            )
        }
    }
}
