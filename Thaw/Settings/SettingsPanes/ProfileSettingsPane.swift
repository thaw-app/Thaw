//
//  ProfileSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var profileManager: ProfileManager

    @State private var newProfileName = ""
    @State private var isApplying = false
    @State private var editingProfileID: UUID?
    @State private var editingName = ""
    @State private var isConfirmingDelete = false
    @State private var profileToDelete: UUID?
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        IceForm {
            IceSection("Profiles") {
                profileList
                createProfileControls
            }

            if !profileManager.profiles.isEmpty {
                IceSection {
                    Text("Auto-Switch").font(.headline)
                } content: {
                    autoSwitchInfo
                    autoSwitchControls
                } footer: {
                    focusFilterFooter
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    // MARK: - Profile List

    @ViewBuilder
    private var profileList: some View {
        if profileManager.profiles.isEmpty {
            Text("No profiles saved. Save your current configuration to create one.")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            ForEach(profileManager.profiles) { profile in
                profileRow(for: profile)
            }
        }
    }

    private func profileRow(for profile: ProfileMetadata) -> some View {
        HStack(spacing: 12) {
            if editingProfileID == profile.id {
                TextField("Profile name", text: $editingName, onCommit: {
                    commitRename(id: profile.id)
                })
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

                Button("Done") {
                    commitRename(id: profile.id)
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                    .opacity(profile.id == profileManager.activeProfileID ? 1 : 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Created: \(profile.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("Modified: \(profile.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Apply") {
                    applyProfile(id: profile.id)
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || profile.id == profileManager.activeProfileID)

                Button("Update") {
                    updateProfile(id: profile.id)
                }
                .buttonStyle(.bordered)
                .help("Overwrite this profile with the current configuration")

                Menu {
                    Button("Rename") {
                        editingProfileID = profile.id
                        editingName = profile.name
                    }

                    Button("Duplicate") {
                        duplicateProfile(id: profile.id)
                    }

                    Button("Export") {
                        exportProfile(id: profile.id, name: profile.name)
                    }

                    Divider()

                    Button("Delete", role: .destructive) {
                        profileToDelete = profile.id
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .alert("Delete Profile?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                if let id = profileToDelete {
                    deleteProfile(id: id)
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            if let id = profileToDelete,
               let profile = profileManager.profiles.first(where: { $0.id == id }) {
                Text("Are you sure you want to delete the profile \"\(profile.name)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Create Profile

    @ViewBuilder
    private var createProfileControls: some View {
        HStack(spacing: 8) {
            TextField("New profile name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)
                .onSubmit {
                    createProfile()
                }

            Button("Save Current") {
                createProfile()
            }
            .buttonStyle(.bordered)
            .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                importProfile()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .help("Import a profile from a file")
        }

        if !profileManager.profiles.isEmpty {
            HStack {
                Spacer()
                Button("Export All Profiles") {
                    exportAllProfiles()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Auto-Switch

    private var autoSwitchInfo: some View {
        Text("Assign a profile to each display.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var focusFilterFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
            VStack(alignment: .leading, spacing: 2) {
                Text("To switch profiles with Focus modes, add Thaw as a Focus Filter in System Settings \u{2192} Focus \u{2192} [Mode] \u{2192} Focus Filters.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("When a Focus mode deactivates, the display profile is automatically restored.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var autoSwitchControls: some View {
        let displays = allDisplays()
        let profileOptions = profileManager.profiles

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
                }
            )

            IcePicker(LocalizedStringKey(display.name), selection: binding) {
                Text("None").tag("")
                ForEach(profileOptions) { profile in
                    Text(profile.name).tag(profile.id.uuidString)
                }
            }
        }
    }

    // MARK: - Actions

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try profileManager.saveProfile(name: name, from: appState)
            profileManager.activeProfileID = profileManager.profiles.last?.id
            newProfileName = ""
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func applyProfile(id: UUID) {
        isApplying = true
        Task {
            do {
                let profile = try profileManager.loadProfile(id: id)
                profileManager.activeProfileID = id
                profileManager.applyProfile(profile, to: appState)
                // Wait for the layout task to complete before re-enabling.
                await profileManager.layoutTask?.value
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            isApplying = false
        }
    }

    private func updateProfile(id: UUID) {
        do {
            try profileManager.updateProfileWithCurrentState(id: id, appState: appState)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func commitRename(id: UUID) {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            editingProfileID = nil
            return
        }
        do {
            try profileManager.renameProfile(id: id, to: name)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        editingProfileID = nil
    }

    private func duplicateProfile(id: UUID) {
        let profile = profileManager.profiles.first { $0.id == id }
        let name = (profile?.name ?? "Profile") + " Copy"
        do {
            try profileManager.duplicateProfile(id: id, newName: name)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func deleteProfile(id: UUID) {
        do {
            try profileManager.deleteProfile(id: id)
            if profileManager.activeProfileID == id {
                profileManager.activeProfileID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func exportProfile(id: UUID, name: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(safeName).json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try profileManager.exportProfile(id: id, to: url)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func exportAllProfiles() {
        guard let json = profileManager.exportAllProfiles() else {
            errorMessage = "Failed to encode profiles for export."
            showingError = true
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Thaw Profiles.json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try json.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try profileManager.importProfile(from: url)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    // MARK: - Display Helpers

    private struct DisplayInfo: Identifiable {
        let id: String
        let name: String
        let isConnected: Bool
    }

    /// Returns all displays relevant to auto-switch: connected displays plus
    /// any disconnected displays that still have a profile association.
    private func allDisplays() -> [DisplayInfo] {
        var displays = NSScreen.screens.compactMap { screen -> DisplayInfo? in
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                return nil
            }
            return DisplayInfo(id: uuid, name: screen.localizedName, isConnected: true)
        }

        let connectedIDs = Set(displays.map(\.id))
        for profile in profileManager.profiles {
            guard let uuid = profile.associatedDisplayUUID,
                  !connectedIDs.contains(uuid)
            else { continue }
            let cachedName = profile.associatedDisplayName ?? uuid
            displays.append(DisplayInfo(
                id: uuid,
                name: "\(cachedName) (disconnected)",
                isConnected: false
            ))
        }

        return displays
    }
}
