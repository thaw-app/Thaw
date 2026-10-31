//
//  PrivacySettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawModuleKit
import ThawUI

/// What the app may see and where anything goes: the permissions it holds,
/// the apps it lets change its settings, the pixels it reads, and the
/// network calls it makes. The move record lives on Troubleshooting, beside
/// the diagnostic log it mirrors.
struct PrivacySettingsPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var updatesManager: UpdatesManager
    @Bindable var advancedSettings: AdvancedSettings

    var body: some View {
        ThawForm {
            SettingsPrivacyNotice(
                title: "Nothing leaves this Mac",
                message: "\(Constants.displayName) collects no analytics or usage data. Permission checks stay on your Mac. The only network calls are the ones listed below, and each has a switch."
            )

            ThawSection("Questions about privacy?") {
                PrivacyQuestionsDisclaimer()
            }

            ThawSection("Permissions") {
                ForEach(appState.permissions.allPermissions) { permission in
                    permissionRow(permission)
                }
            }

            OtherAppsSection(settings: appState.settings.automation)

            CaptureInspectorSection()

            // Only while the status icon is on: with it off nothing reads the
            // connection, so there is nothing to account for.
            if appState.moduleHost.isEnabled(.widgets) {
                ThawSection("Local connection status") {
                    Text("The widget icon reads the connection type from macOS on this Mac. It does not contact a server or send network details, and it stops reading when you turn Widgets off in Extras.")
                        .foregroundStyle(ThawInk.supporting)
                }
            }

            ThawSection("Network access") {
                networkAccess
            }
        }
    }

    // MARK: Permissions

    /// One permission: what it is, why the app asks, and the control that
    /// changes it.
    private func permissionRow(_ permission: Permission) -> some View {
        HStack(alignment: .firstTextBaseline) {
            PermissionLabel(permission: permission)
            Spacer()
            PermissionStatusControl(permission: permission)
        }
        .annotation {
            Text(permission.details.joined(separator: " "))
        }
    }

    // MARK: Network access

    @ViewBuilder
    private var networkAccess: some View {
        if Constants.supportsSparkleUpdates {
            // One picker, not two switches: downloading implies checking.
            ThawPicker("Automatic updates", selection: $updatesManager.automaticUpdates) {
                ForEach(AutomaticUpdates.allCases) { mode in
                    Text(mode.localized).tag(mode)
                }
            }
            .annotation {
                Text("Checking asks \(updateHost) whether a newer version exists. Downloading also fetches it in the background; without it, the download starts only after you accept an update. The release notes shown with an update come from the same server.")
            }

            Toggle(isOn: $advancedSettings.fetchReleaseNotes) {
                Text("What’s New notes")
            }
            .annotation {
                Text("Fetches the latest release notes from \(changelogHost) when you open What’s New and keeps a copy for offline use. When this is off, What’s New shows the last copy it fetched, if there is one.")
            }
        } else {
            Text("This build of \(Constants.displayName) makes no network calls.")
                .foregroundStyle(ThawInk.supporting)
        }
    }

    /// Read from the updater's own Info.plist key so the row cannot name a
    /// different server. NetworkAccessInventoryTests keeps the list complete.
    private var updateHost: String {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        return feed.flatMap(URL.init(string:))?.host ?? String(localized: "the update server")
    }

    private var changelogHost: String {
        Constants.changelogURL.host ?? String(localized: "the repository")
    }
}
