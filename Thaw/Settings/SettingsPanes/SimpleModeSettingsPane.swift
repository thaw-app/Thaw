//
//  SimpleModeSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import MenuBarModel
import SwiftUI
import ThawCapture
import ThawUI

/// Simple Mode's one page. Every other setting keeps working in the full window.
struct SimpleModeSettingsPane: View {
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager
    let updatesManager: UpdatesManager
    @Bindable var settings: GeneralSettings

    var body: some View {
        ThawForm {
            if !appState.permissions.accessibility.hasPermission {
                accessibilityPill
            }
            if settings.simpleModeShowsPreview {
                preview
            }
            ThawSection {
                howItWorks
            }
            ThawSection {
                LaunchAtLoginRow()
                arrangementPicker
                RehideChoiceRow(settings: appState.settings.visibility)
                alwaysHiddenToggle
                previewToggle
                hiddenSectionHotkeyRow
                updatesToggle
            }
        }
    }

    // MARK: Preview

    /// The sections as they are now. Icons can be dragged here too.
    @ViewBuilder
    private var preview: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            SettingsWarningPill(
                title: "The menu bar is set to hide itself",
                message: "\(Constants.displayName) can't arrange items while macOS auto-hides the menu bar. Turn that off in System Settings.",
                systemImage: "menubar.arrow.up.rectangle",
                actionTitle: "Open System Settings"
            ) {
                Constants.openMenuBarSystemSettings()
            }
        } else {
            ThawSection {
                FoldedMenuBar(itemManager: itemManager)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                if !ScreenCapture.hasCachedScreenRecordingPermission {
                    SettingsWarningPill(
                        title: "Showing app icons",
                        message: "Add Screen Recording to see your real menu bar icons instead.",
                        systemImage: "eye.slash",
                        actionTitle: "Grant Access",
                        action: { appState.permissions.screenRecording.performRequest() }
                    )
                }
            }
        }
    }

    // MARK: How it works

    private var howItWorks: some View {
        Label {
            Text("Hold ⌘ and drag icons to the left of the divider in your menu bar to hide them. Click \(Constants.displayName)'s icon to show them again.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "hand.draw")
                .foregroundStyle(ThawInk.supporting)
        }
    }

    // MARK: Settings

    /// The same choice as on Layout, so Simple Mode doesn't decide it for you.
    private var arrangementPicker: some View {
        @Bindable var layout = appState.settings.layout
        return ThawPillPicker(
            "Item arrangement",
            selection: $layout.menuBarArrangementMode,
            values: MenuBarArrangementMode.allCases,
            title: \.localized
        )
        .annotation(layout.menuBarArrangementMode.explanation)
    }

    private var previewToggle: some View {
        Toggle("Sections preview", isOn: $settings.simpleModeShowsPreview)
            .annotation("Shows your Visible, Hidden and Always Hidden items at the top of this page.")
    }

    private var alwaysHiddenToggle: some View {
        @Bindable var layout = appState.settings.layout
        return Toggle("Always Hidden", isOn: $layout.enableAlwaysHiddenSection)
            .annotation("Adds a second divider. Icons left of it stay hidden until you double-click \(Constants.displayName)'s icon.")
    }

    /// Gated the way the Shortcuts pane gates it: no recorder for a section
    /// that is disabled.
    @ViewBuilder
    private var hiddenSectionHotkeyRow: some View {
        if appState.menuBarManager.section(withName: .hidden)?.isEnabled == true,
           let hotkey = appState.settings.hotkeys.hotkey(withAction: .toggleHiddenSection)
        {
            HotkeyRecorder(hotkey: hotkey) {
                Text("Shortcut to show and hide")
            }
        }
    }

    private var updatesToggle: some View {
        @Bindable var updatesManager = updatesManager
        return Toggle("Check for updates automatically", isOn: $updatesManager.automaticallyChecksForUpdates)
    }

    // MARK: Permissions

    /// Hiding needs Accessibility, so its absence is the one warning worth the space.
    private var accessibilityPill: some View {
        SettingsWarningPill(
            title: "Accessibility is off",
            message: "\(Constants.displayName) needs Accessibility to hide and show menu bar items.",
            systemImage: "lock",
            actionTitle: "Grant Access",
            action: { appState.permissions.accessibility.performRequest() }
        )
    }
}
