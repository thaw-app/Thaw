//
//  SimpleModeSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The entire settings surface while Simple Mode is on.
///
/// One page, no navigation. Sections are ordered by how often someone in this
/// mode needs them: arranging the bar is the reason the mode exists, the
/// behavior rows change daily life, and app plumbing sits at the bottom next
/// to a compact about footer. Everything the full window grows around — hover
/// delays, rehide strategies, gesture variants — is tuning, and tuning is what
/// turning Simple Mode off is for.
///
/// Nothing is disabled. Every other pane keeps its configuration and stays
/// reachable through the settings URI, and turning Simple Mode off brings the
/// full sidebar straight back.
struct SimpleModeSettingsPane: View {
    @Environment(AppState.self) private var appState: AppState
    let itemManager: MenuBarItemManager
    let updatesManager: UpdatesManager
    @Bindable var settings: GeneralSettings

    /// Mirrors ``MenuBarLayoutSettingsPane``: arranging is blocked only while
    /// the system is hiding the menu bar itself.
    private var canArrangeLayout: Bool {
        !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults
    }

    private var missingPermissions: [Permission] {
        appState.permissions.allPermissions.filter { !$0.hasPermission }
    }

    var body: some View {
        IceForm {
            arrangeSection
            behaviorSection
            appSection
            if !missingPermissions.isEmpty {
                permissionsSection
            }
            aboutSection
        }
    }

    // MARK: - Arrange

    @ViewBuilder
    private var arrangeSection: some View {
        if !canArrangeLayout {
            IceSection {
                Text("\(Constants.displayName) cannot arrange menu bar items in automatically hidden menu bars.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            LayoutBarsSection(itemManager: itemManager)
            LayoutResetControls(
                itemManager: itemManager,
                controlItemsDisabled: itemManager.areControlItemsMissing,
                alwaysHiddenEnabled: appState.settings.advanced.enableAlwaysHiddenSection
            )
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        IceSection("Behavior") {
            ShowHiddenItemsOnRow(settings: settings)
            AutoRehideRow(settings: settings)
        }
    }

    // MARK: - App

    private var appSection: some View {
        IceSection("\(Constants.displayName)") {
            LaunchAtLoginRow()
            ShowIceIconRow(settings: settings)
            Toggle("Simple Mode", isOn: $settings.simpleMode)
                .annotation("Turn off to show every setting. Nothing you configure here is lost either way.")
        }
    }

    // MARK: - Permissions

    /// Shown only while something is missing; a fully-granted list is noise.
    private var permissionsSection: some View {
        IceSection {
            Text("Permissions")
        } content: {
            ForEach(missingPermissions) { permission in
                HStack(spacing: 8) {
                    Label(permission.title, systemImage: permission.iconName)
                        .foregroundStyle(permission.iconColor)
                    Spacer()
                    Button("Enable") {
                        permission.performRequest()
                    }
                }
            }
        } footer: {
            Text("Accessibility is all Simple Mode needs for hiding and arranging; adding Screen Recording draws your real menu bar icons in the layout editor.")
        }
    }

    // MARK: - About

    /// The essentials of the full About pane: version and update checking.
    /// Support links and acknowledgements live in the full window's About pane.
    private var aboutSection: some View {
        IceSection {
            Text("About")
        } content: {
            HStack {
                Text("\(Constants.displayName) \(Constants.versionString)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates") {
                    updatesManager.checkForUpdates()
                }
            }
        }
    }
}
