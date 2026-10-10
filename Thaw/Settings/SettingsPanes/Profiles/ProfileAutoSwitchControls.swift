//
//  ProfileAutoSwitchControls.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI

/// Display and Space switching lives in Automation, linked from Profiles.
/// ProfileManager bindings preserve manifest-failure reporting and Space-key behavior.
struct ProfileAutoSwitchControls: View {
    let profileManager: ProfileManager
    @Environment(AppState.self) private var appState

    @Binding var errorMessage: String?

    var body: some View {
        ThawSection {
            Text("Profile switching by display")
        } content: {
            Text("Assign a profile to each display.")
                .font(.callout)
                .foregroundStyle(ThawInk.supporting)
            autoSwitchControls
        } footer: {
            focusFilterFooter
        }

        ThawSection {
            Text("Profile switching by Space")
        } content: {
            spaceAutoSwitchControls
        } footer: {
            Text("Assigns a profile to the Space you are currently on. Spaces have no system name, so each assignment is labeled by its Mission Control position at the time you made it. A Space assignment takes precedence over a display assignment; a Focus Filter still overrides both.")
        }
    }

    // MARK: - Display auto-switch

    @ViewBuilder
    private var autoSwitchControls: some View {
        let displays = allKnownDisplays
        let profileOptions = profileManager.profiles

        if displays.isEmpty {
            Text("No displays are known yet.")
                .foregroundStyle(ThawInk.supporting)
                .font(.callout)
        } else {
            ForEach(displays) { display in
                let binding = Binding<String>(
                    get: {
                        profileOptions.first(where: { $0.associatedDisplayUUID == display.id })?.id.uuidString ?? ""
                    },
                    set: { newValue in
                        profileManager.setAssociatedDisplay(uuid: nil, forDisplayUUID: display.id)
                        if let profileID = UUID(uuidString: newValue) {
                            profileManager.setAssociatedDisplay(
                                uuid: display.id,
                                displayName: display.name,
                                forProfileID: profileID
                            )
                        }
                        reportManifestFailure()
                    }
                )

                ThawPicker(selection: binding) {
                    Text("None").tag("")
                    ForEach(profileOptions) { profile in
                        Text(profile.name).tag(profile.id.uuidString)
                    }
                } label: {
                    display.localizedLabel
                }
            }
        }
    }

    private var focusFilterFooter: some View {
        SettingsWarningPill(
            title: "Focus Filters",
            message: "To switch profiles with Focus modes, add \(Constants.displayName) as a Focus Filter in System Settings \(Constants.menuArrow) Focus \(Constants.menuArrow) [Mode] \(Constants.menuArrow) Focus Filters. When a Focus mode deactivates, the display profile is automatically restored.",
            systemImage: "info.circle.fill",
            actionTitle: "Open Focus Settings"
        ) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Focus") {
                NSWorkspace.shared.open(url)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Space auto-switch

    @ViewBuilder
    private var spaceAutoSwitchControls: some View {
        let profileOptions = profileManager.profiles
        let activeSpace = appState.activeSpace
        let activeKey = activeSpace.persistentKey

        if let activeKey {
            let binding = Binding<String>(
                get: {
                    profileOptions.first(where: { $0.associatedSpaceKey == activeKey })?.id.uuidString ?? ""
                },
                set: { newValue in
                    if let profileID = UUID(uuidString: newValue) {
                        profileManager.setAssociatedSpace(
                            key: activeKey,
                            spaceName: activeSpace.localizedLabel,
                            forProfileID: profileID
                        )
                    } else if let current = profileOptions.first(where: { $0.associatedSpaceKey == activeKey }) {
                        profileManager.setAssociatedSpace(key: nil, forProfileID: current.id)
                    }
                    reportManifestFailure()
                }
            )

            ThawPicker(selection: binding) {
                Text("None").tag("")
                ForEach(profileOptions) { profile in
                    Text(profile.name).tag(profile.id.uuidString)
                }
            } label: {
                Text(activeSpace.localizedLabel)
            }
        } else {
            Text("The active Space is still settling. Switch to it again to assign a profile.")
                .foregroundStyle(ThawInk.supporting)
        }

        let assigned = profileManager.profiles.filter { $0.associatedSpaceKey != nil }
        if !assigned.isEmpty {
            ForEach(assigned) { profile in
                HStack {
                    Text(profile.associatedSpaceName ?? profile.associatedSpaceKey ?? "")
                    Spacer()
                    Text(profile.name)
                        .foregroundStyle(ThawInk.supporting)
                    Button("Remove") {
                        profileManager.setAssociatedSpace(key: nil, forProfileID: profile.id)
                        reportManifestFailure()
                    }
                    .buttonStyle(.settingsGlass)
                }
            }
        }
    }

    // MARK: - Helpers

    private func reportManifestFailure() {
        if let message = profileManager.takeManifestError() {
            errorMessage = message
        }
    }

    private var allKnownDisplays: [DisplayInfo] {
        let knownDisplays = appState.settings.displaySettings.knownDisplays
        var displays = NSScreen.managedScreens.compactMap { screen -> DisplayInfo? in
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                return nil
            }
            return DisplayInfo(
                id: uuid,
                name: screen.localizedName,
                hasNotch: screen.hasNotch,
                isConnected: true
            )
        }

        let connectedIDs = Set(displays.map(\.id))
        for profile in profileManager.profiles {
            guard let uuid = profile.associatedDisplayUUID,
                  !connectedIDs.contains(uuid)
            else { continue }
            let cachedName = profile.associatedDisplayName ?? uuid
            displays.append(DisplayInfo(
                id: uuid,
                name: cachedName,
                hasNotch: knownDisplays[uuid]?.hasNotch ?? false,
                isConnected: false
            ))
        }

        return displays
    }

    private struct DisplayInfo: Identifiable {
        let id: String
        let name: String
        let hasNotch: Bool
        let isConnected: Bool

        var localizedLabel: some View {
            HStack(spacing: 6) {
                Text(name)
                if hasNotch {
                    Text("Notch")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                if !isConnected {
                    Text("Disconnected")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
        }
    }
}
