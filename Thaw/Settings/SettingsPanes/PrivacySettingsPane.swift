//
//  PrivacySettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// What the app may see and where anything goes: the permissions it holds,
/// the pixels it reads, and the network calls it makes. The move record
/// lives on Tools, beside the diagnostic log it mirrors.
struct PrivacySettingsPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var updatesManager: UpdatesManager
    @Bindable var advancedSettings: AdvancedSettings

    var body: some View {
        ThawForm {
            // Footer-only section: the one placement where a pill renders
            // without the grouped form's section card around it.
            ThawSection {
                EmptyView()
            } footer: {
                SettingsWarningPill(
                    title: "Nothing leaves this Mac",
                    message: "\(Constants.displayName) collects no analytics or usage data. Permission checks stay on your Mac. The only network calls are the ones listed below, and each has a switch.",
                    systemImage: "hand.raised.fill",
                    tint: .green
                )
            }

            ThawSection("Questions about privacy?") {
                PrivacyQuestionsDisclaimer()
            }

            ThawSection("Permissions") {
                ForEach(appState.permissions.allPermissions) { permission in
                    permissionRow(permission)
                }
            }

            CaptureInspectorSection()

            // Only while the status icon is on: with it off nothing reads the
            // connection, so there is nothing to account for.
            if StatusIconWidgetController.shared.isEnabled {
                ThawSection("Local connection status") {
                    Text("The custom status icon reads the connection type from macOS on this Mac. It does not contact a server or send network details, and it stops reading when you turn the custom status icon off.")
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
            ThawPicker("Automatic updates", selection: automaticUpdatesMode) {
                Text("Off").tag(AutomaticUpdates.off)
                Text("Check only").tag(AutomaticUpdates.check)
                Text("Check and download").tag(AutomaticUpdates.download)
            }
            .annotation {
                Text("Checking asks \(updateHost) whether a newer version exists. Downloading also fetches it in the background; without it, the download starts only after you accept an update.")
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Update release notes")
                Spacer()
                Text("With the update")
                    .foregroundStyle(ThawInk.supporting)
            }
            .annotation {
                Text("\(Constants.displayName) loads these from \(updateHost) when it shows you an update. They are part of the update, so they follow the automatic updates setting.")
            }

            Toggle(isOn: $advancedSettings.fetchReleaseNotes) {
                Text("What’s New notes")
            }
            .annotation {
                Text("Fetches the latest release notes from \(changelogHost) when you open What’s New and keeps a copy for offline use. When this is off, What’s New shows the last copy it fetched, if there is one.")
            }

            // Hidden once everything is off, when it would do nothing.
            if updatesManager.automaticallyChecksForUpdates
                || updatesManager.automaticallyDownloadsUpdates
                || advancedSettings.fetchReleaseNotes
            {
                HStack {
                    Spacer()
                    Button("Turn Everything Off") {
                        updatesManager.automaticallyChecksForUpdates = false
                        updatesManager.automaticallyDownloadsUpdates = false
                        advancedSettings.fetchReleaseNotes = false
                    }
                    .buttonStyle(.settingsGlass)
                }
            }
        } else {
            Text("This build of \(Constants.displayName) makes no network calls.")
                .foregroundStyle(ThawInk.supporting)
        }
    }

    private enum AutomaticUpdates: Hashable {
        case off, check, download
    }

    private var automaticUpdatesMode: Binding<AutomaticUpdates> {
        Binding {
            if !updatesManager.automaticallyChecksForUpdates {
                return .off
            }
            return updatesManager.automaticallyDownloadsUpdates ? .download : .check
        } set: { mode in
            updatesManager.automaticallyChecksForUpdates = mode != .off
            updatesManager.automaticallyDownloadsUpdates = mode == .download
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
