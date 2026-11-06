//
//  ProfileSwitchesSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Everything that switches to one profile. A display or Space belongs to one profile at a time,
/// so choosing it here takes it from any other.
struct ProfileSwitchesSection: View {
    @Environment(AppState.self) private var appState
    @Bindable var profileManager: ProfileManager
    let displaySettings: DisplaySettingsManager
    let profile: ProfileMetadata
    @Binding var errorMessage: String?

    var body: some View {
        ThawSection {
            Text("What switches to this profile")
        } content: {
            if let hotkey = profileManager.profileHotkeys[profile.id] {
                HotkeyRecorder(hotkey: hotkey) {
                    Text("Keyboard shortcut")
                }
                // The recorder keeps its capture in State, so a new profile needs a new recorder.
                .id(profile.id)
            }
            displayPicker
            spaceRow
            focusRow
        } footer: {
            Text("A Space takes priority over a display, and a Focus filter over both.")
                .font(ThawType.footnote)
                .foregroundStyle(ThawInk.supporting)
        }
    }

    // MARK: Display

    private var displayPicker: some View {
        ThawPicker(selection: displayBinding) {
            Text("None").tag("")
            ForEach(knownDisplays) { display in
                Text(Self.label(for: display)).tag(display.id)
            }
        } label: {
            ThawRowLabel("On this display", detail: "Switches when the menu bar moves to it.")
        }
    }

    private var displayBinding: Binding<String> {
        Binding {
            profileManager.profiles.first { $0.id == profile.id }?.associatedDisplayUUID ?? ""
        } set: { uuid in
            let display = knownDisplays.first { $0.id == uuid }
            profileManager.setAssociatedDisplay(
                uuid: uuid.isEmpty ? nil : uuid,
                displayName: display?.name,
                forProfileID: profile.id
            )
            reportManifestFailure()
        }
    }

    private var knownDisplays: [DisplaySettingsManager.DisplayInfo] {
        Self.displayChoices(connected: displaySettings.connectedDisplays(), profiles: profileManager.profiles)
    }

    /// Connected displays, plus a disconnected one this profile or another
    /// still names, so its choice stays visible.
    static func displayChoices(
        connected: [DisplaySettingsManager.DisplayInfo],
        profiles: [ProfileMetadata]
    ) -> [DisplaySettingsManager.DisplayInfo] {
        var displays = connected
        for profile in profiles {
            guard let uuid = profile.associatedDisplayUUID, !displays.contains(where: { $0.id == uuid }) else { continue }
            displays.append(DisplaySettingsManager.DisplayInfo(
                id: uuid,
                displayID: nil,
                name: profile.associatedDisplayName ?? uuid,
                hasNotch: false,
                isConnected: false
            ))
        }
        return displays
    }

    /// A display's name in the picker, with Notch or Disconnected after it.
    static func label(for display: DisplaySettingsManager.DisplayInfo) -> String {
        var parts = [display.name]
        if display.hasNotch {
            parts.append(String(localized: "Notch"))
        }
        if !display.isConnected {
            parts.append(String(localized: "Disconnected"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Space

    private var spaceRow: some View {
        let current = profileManager.profiles.first { $0.id == profile.id }
        let activeSpace = appState.activeSpace
        let activeKey = activeSpace.persistentKey
        return LabeledContent {
            HStack(spacing: ThawSpacing.base) {
                if current?.associatedSpaceKey != nil {
                    Button("Remove") {
                        profileManager.setAssociatedSpace(key: nil, forProfileID: profile.id)
                        reportManifestFailure()
                    }
                    .buttonStyle(.settingsGlass)
                }
                if let activeKey, current?.associatedSpaceKey != activeKey {
                    Button("Use This Space") {
                        profileManager.setAssociatedSpace(key: activeKey, spaceName: activeSpace.localizedLabel, forProfileID: profile.id)
                        reportManifestFailure()
                    }
                    .buttonStyle(.settingsGlass)
                }
            }
        } label: {
            ThawRowLabel(
                "In this Space",
                verbatimDetail: current?.associatedSpaceKey == nil
                    ? String(localized: "None. \(Constants.displayName) names a Space by its place in Mission Control.")
                    : current?.associatedSpaceName ?? String(localized: "A Space")
            )
        }
    }

    // MARK: Focus

    private var focusRow: some View {
        LabeledContent {
            Button("Open Focus Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Focus") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.settingsGlass)
        } label: {
            ThawRowLabel(
                "With a Focus",
                detail: "Add \(Constants.displayName) as a Focus filter in System Settings > Focus and pick this profile. When the Focus ends, the display's profile comes back."
            )
        }
    }

    private func reportManifestFailure() {
        if let message = profileManager.takeManifestError() {
            errorMessage = message
        }
    }
}
