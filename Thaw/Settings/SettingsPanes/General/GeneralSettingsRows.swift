//
//  GeneralSettingsRows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// General settings shared by GeneralSettingsPane and SimpleModeSettingsPane,
// defined once so the two panes' explanations cannot drift.

// MARK: - LaunchAtLoginRow

/// Whether the app starts with the user's session.
struct LaunchAtLoginRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let setting = appState.settings.launchAtLogin
        Toggle("Launch at Login", isOn: Binding(
            get: { setting.isEnabled },
            set: { enabled in
                Task { await setting.setEnabled(enabled) }
            }
        ))
        .disabled(!setting.isLoaded || setting.isUpdating)
        .task {
            let activations = NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification)
            await setting.refresh()
            for await _ in activations {
                await setting.refresh()
            }
        }
    }
}

// MARK: - ShowThawIconRow

/// Whether the app's own menu bar icon is shown, and which icon it is.
struct ShowThawIconRow: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: GeneralSettings
    @State private var placementBlock: ControlItem.PlacementBlock?

    /// Names only the gestures that currently do something: double-click needs
    /// Always Hidden, and the swap option changes what a click does.
    private var gestureSummary: LocalizedStringKey {
        let advanced = appState.settings.advanced
        let doubleClickOpensAlwaysHidden = advanced.isAlwaysHiddenSectionEnabled
        switch (advanced.swapOnThawIconClick, doubleClickOpensAlwaysHidden) {
        case (false, true):
            return "Click to show hidden items, double-click for Always Hidden, and right-click for settings."
        case (false, false):
            return "Click to show hidden items and right-click for settings."
        case (true, true):
            return "Click to swap shown and hidden items, double-click for Always Hidden, and right-click for settings."
        case (true, false):
            return "Click to swap shown and hidden items and right-click for settings."
        }
    }

    var body: some View {
        Toggle("Show \(Constants.displayName) icon", isOn: $settings.showThawIcon)
            .annotation(gestureSummary)
            .task {
                guard let item = appState.menuBarManager.controlItem(withName: .visible) else { return }
                for await block in item.$placementBlock.values {
                    placementBlock = block
                }
            }
        if settings.showThawIcon {
            ThawIconPicker(settings: settings)
            if let placementBlock {
                missingIconPill(for: placementBlock)
            }
        }
    }

    /// Says why the icon is missing while the switch above reads on.
    private func missingIconPill(for block: ControlItem.PlacementBlock) -> some View {
        let title: LocalizedStringKey = switch block {
        case .deniedBySystem: "macOS isn't allowing \(Constants.displayName) in the menu bar"
        case .unknown: "The \(Constants.displayName) icon isn't in the menu bar"
        }
        let message: LocalizedStringKey = switch block {
        case .deniedBySystem: "Switch \(Constants.displayName) back on in System Settings > Menu Bar."
        case .unknown: "macOS may be blocking it. Check that \(Constants.displayName) is switched on in System Settings > Menu Bar."
        }
        return SettingsWarningPill(
            title: title,
            message: message,
            tint: .orange,
            actionTitle: "Open System Settings"
        ) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - ShowHiddenItemsOnRow

/// Which gestures on an empty stretch of the menu bar reveal hidden items.
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
