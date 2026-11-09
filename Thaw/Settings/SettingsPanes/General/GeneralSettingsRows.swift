//
//  GeneralSettingsRows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// General settings rows, some also shown on Simple Mode's page, defined once
// so their explanations cannot drift.

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
        .settingsSearchAnchor("general.launchAtLogin")
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
    /// its shortcut enabled, and the swap option changes what a click does.
    private var gestureSummary: LocalizedStringResource {
        let visibility = appState.settings.visibility
        let doubleClickOpensAlwaysHidden = appState.settings.usesIconDoubleClickForAlwaysHidden
        switch (visibility.swapOnThawIconClick, doubleClickOpensAlwaysHidden) {
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
            .settingsSearchAnchor("general.showThawIcon")
            .annotation(gestureSummary)
            .task {
                guard let item = appState.menuBarManager.controlItem(withName: .visible) else { return }
                for await block in item.$placementBlock.values {
                    placementBlock = block
                }
            }
        if settings.showThawIcon {
            ThawIconPicker(settings: settings)
                .settingsSearchAnchor("general.thawIcon")
            if let placementBlock {
                ThawPlacementWarning(block: placementBlock)
            }
        } else {
            Text("Hiding the icon also shrinks the section dividers to nothing. If items start landing in the wrong section, show the icon again.")
                .font(ThawType.footnote)
                .foregroundStyle(.secondary)
        }
        if !settings.showThawIcon, placementBlock == .deniedBySystem {
            // The dividers are switched off with the icon, so this matters with the icon hidden too.
            ThawPlacementWarning(block: .deniedBySystem)
        }
    }
}

/// Says why Thaw's own items are missing from the menu bar, with the way to the switch.
struct ThawPlacementWarning: View {
    let block: ControlItem.PlacementBlock

    var body: some View {
        let title: LocalizedStringResource = switch block {
        case .deniedBySystem: "macOS isn't allowing \(Constants.displayName) in the menu bar"
        case .unknown: "The \(Constants.displayName) icon isn't in the menu bar"
        }
        let message: LocalizedStringResource = switch block {
        case .deniedBySystem: "\(Constants.displayName) can't hide or arrange anything until it is switched back on in System Settings \(Constants.menuArrow) Menu Bar."
        case .unknown: "macOS may be blocking it. Check that \(Constants.displayName) is switched on in System Settings \(Constants.menuArrow) Menu Bar."
        }
        return SettingsWarningPill(
            title: title,
            message: message,
            tint: .orange,
            actionTitle: "Open System Settings"
        ) {
            Constants.openMenuBarSystemSettings()
        }
    }
}

// MARK: - ShowHiddenItemsOnRow

/// Which gestures on an empty stretch of the menu bar reveal hidden items.
struct ShowHiddenItemsOnRow: View {
    @Bindable var settings: VisibilitySettings

    var body: some View {
        ToggleButtonRow("Show hidden items on") {
            Toggle("Click", isOn: $settings.showOnClick)
                .settingsSearchAnchor("general.showOnClick")
                .help("Click an empty area of the menu bar to show hidden menu bar items.")
            Toggle("Hover", isOn: $settings.showOnHover)
                .settingsSearchAnchor("general.showOnHover")
                .help("Hover over an empty area of the menu bar or the \(Constants.displayName) icon to show hidden menu bar items.")
            Toggle("Scroll", isOn: $settings.showOnScroll)
                .settingsSearchAnchor("general.showOnScroll")
                .help("Scroll or swipe in the menu bar to show hidden menu bar items.")
        }
        .annotation("Show hidden menu bar items by clicking, hovering, or scrolling in an empty area of the menu bar.")
    }
}

// MARK: - ToggleButtonRow

/// One setting that can apply at several times, as a row of buttons that
/// switch on separately, such as Show hidden items on Click, Hover and Scroll.
struct ToggleButtonRow<Toggles: View>: View {
    private let label: LocalizedStringResource
    private let toggles: Toggles

    init(_ label: LocalizedStringResource, @ViewBuilder toggles: () -> Toggles) {
        self.label = label
        self.toggles = toggles()
    }

    var body: some View {
        LabeledContent(label) {
            ThawTogglePills {
                toggles
            }
            .fixedSize()
        }
    }
}

// MARK: - RehideChoiceRow

/// When revealed items hide themselves again, as one menu over the three stored settings.
struct RehideChoiceRow: View {
    @Bindable var settings: VisibilitySettings

    private var choice: SimpleRehideChoice {
        SimpleRehideChoice(autoRehide: settings.autoRehide, strategy: settings.rehideStrategy, interval: settings.rehideInterval)
    }

    var body: some View {
        ThawPicker("Hide items again", selection: Binding(
            get: { choice },
            set: { newChoice in
                let saved = newChoice.settings(keepingInterval: settings.rehideInterval)
                settings.autoRehide = saved.autoRehide
                if let strategy = saved.strategy {
                    settings.rehideStrategy = strategy
                }
                settings.rehideInterval = saved.interval
            }
        )) {
            ForEach(SimpleRehideChoice.options(including: choice)) { option in
                Text(option.title).tag(option)
            }
        }
        .settingsSearchAnchor("general.autoRehide")
        .annotation(choice.explanation)
    }
}
