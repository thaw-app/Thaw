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

/// One page on the sampled menu-bar surface, ordered by arranging, reveal behavior, app controls, then About.
/// Other panes retain configuration and URI access; the toolbar overflow restores the sidebar even with descriptions off, and the title bar names the mode.
struct SimpleModeSettingsPane: View {
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager
    let updatesManager: UpdatesManager
    @Bindable var settings: GeneralSettings

    /// Observe tag membership, not cache geometry, to avoid jitter (MenuBarLayoutGroupsSection).
    @State private var isNothingHidden = false

    /// Block arranging only when macOS hides the bar, as in the full Layout pane.
    /// Accessibility alone suffices; missing Screen Recording or failed crops fall back to owning-app icons.
    private var canArrangeLayout: Bool {
        !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults
    }

    private var missingPermissions: [Permission] {
        appState.permissions.allPermissions.filter { !$0.hasPermission }
    }

    /// Match the full Layout pane's first-run hint conditions.
    private var showsHideByDragHint: Bool {
        FirstRunHintStore.shared.isPending(.hideByDrag) && isNothingHidden
    }

    private func syncHiddenSectionOccupancy() {
        isNothingHidden = itemManager.managedItems(for: .hidden).isEmpty
            && itemManager.managedItems(for: .alwaysHidden).isEmpty
    }

    var body: some View {
        ThawForm {
            arrangeSection
            revealSection
            appSection
            if !missingPermissions.isEmpty {
                permissionsSection
            }
            aboutRow
        }
        .thawAnimation(ThawMotion.settle, value: showsHideByDragHint)
        .onChange(of: itemManager.managedItemTags, initial: true) {
            syncHiddenSectionOccupancy()
        }
    }

    // MARK: - Arrange

    /// No header: the folded bar is the page's own opening line. Reset
    /// hangs beneath it as a footnote.
    @ViewBuilder
    private var arrangeSection: some View {
        if !canArrangeLayout {
            cannotArrangePill
        } else {
            @Bindable var advanced = appState.settings.advanced
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
                if showsHideByDragHint {
                    ThawFirstRunHint(
                        systemImage: "hand.draw",
                        "Drag an icon into Hidden to tuck it away. Click \(Constants.displayName)'s icon in the menu bar to bring it back."
                    ) {
                        FirstRunHintStore.shared.dismiss(.hideByDrag)
                    }
                }
                // The arrangement choice sits under the bar. Mirrors the full
                // Layout pane's first row so Simple Mode stays self-contained.
                ThawPicker("Item arrangement", selection: $advanced.menuBarArrangementMode) {
                    ForEach(MenuBarArrangementMode.allCases) { mode in
                        Text(mode.localized).tag(mode)
                    }
                }
                .annotation(appState.settings.advanced.menuBarArrangementMode.explanation)
            } footer: {
                LayoutResetFlow(
                    itemManager: itemManager,
                    controlItemsDisabled: itemManager.areControlItemsMissing,
                    alwaysHiddenEnabled: appState.settings.advanced.enableAlwaysHiddenSection,
                    presentation: .footnote
                )
            }
        }
    }

    /// The full pane replaces itself with a sentence here. Simple Mode keeps
    /// the rest of the page usable and says where the switch is.
    private var cannotArrangePill: some View {
        SettingsWarningPill(
            title: "The menu bar is set to hide itself",
            message: "\(Constants.displayName) can't arrange items while macOS auto-hides the menu bar. Turn that off in System Settings.",
            systemImage: "menubar.arrow.up.rectangle",
            actionTitle: "Open System Settings"
        ) {
            if let url = Constants.menuBarSystemSettingsURL {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Reveal

    /// How hidden items come back: the trigger, whether they go away again,
    /// and the one shortcut worth having.
    private var revealSection: some View {
        ThawSection("Reveal") {
            Toggle("Use \(Constants.displayName) Bar", isOn: useThawBarBinding)
                .annotation("Show hidden menu bar items in a separate bar below the menu bar.")
            ShowHiddenItemsOnRow(settings: settings)
            AutoRehideRow(settings: settings)
            hiddenSectionHotkeyRow
        }
    }

    /// Binds to the display with the menu bar, the one Simple Mode is about.
    private var useThawBarBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.displaySettings.configurationForActiveDisplay().useThawBar },
            set: { newValue in
                guard let uuid = Bridging.getActiveMenuBarDisplayUUID() else { return }
                appState.settings.displaySettings.updateConfiguration(forDisplayUUID: uuid) {
                    $0.withUseThawBar(newValue)
                }
            }
        )
    }

    /// Gated the way the Hotkeys pane gates it: no recorder for a section
    /// that is disabled.
    @ViewBuilder
    private var hiddenSectionHotkeyRow: some View {
        if appState.menuBarManager.section(withName: .hidden)?.isEnabled == true,
           let hotkey = appState.settings.hotkeys.hotkey(withAction: .toggleHiddenSection)
        {
            HotkeyRecorder(hotkey: hotkey) {
                Text("Toggle the Hidden section")
            }
        }
    }

    // MARK: - App

    /// Keep the descriptions toggle reachable here so Simple Mode can restore annotations disabled in the full window.
    private var appSection: some View {
        ThawSection("App") {
            LaunchAtLoginRow()
            ShowThawIconRow(settings: settings)
            Toggle("Show setting descriptions", isOn: $settings.showSettingDescriptions)
                .annotation("Explains what a setting does directly beneath it, like this text.")
        }
    }

    // MARK: - Permissions

    /// Shown only while something is missing; a fully-granted list is noise.
    private var permissionsSection: some View {
        ThawSection {
            Text("Permissions")
        } content: {
            ForEach(missingPermissions) { permission in
                HStack(spacing: 8) {
                    PermissionLabel(permission: permission)
                    Spacer()
                    PermissionStatusControl(permission: permission)
                }
            }
        } footer: {
            Text("Accessibility is all Simple Mode needs. Arranging, groups, and hiding work without Screen Recording; adding it draws your real icons in Layout, the \(Constants.displayName) Bar, and Search.")
        }
    }

    // MARK: - About

    /// One caption line, no card: version and an updates check. Support links
    /// and acknowledgements live in the full window's About pane.
    private var aboutRow: some View {
        HStack(spacing: 12) {
            Text("\(Constants.displayName) \(Constants.versionString)")
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
            Spacer()
            Button("Check for Updates") {
                updatesManager.checkForUpdates()
            }
            .buttonStyle(.settingsGlass)
            .font(ThawType.label)
        }
        .listRowBackground(Color.clear)
    }
}
