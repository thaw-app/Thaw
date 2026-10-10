//
//  ProfileSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI
import UniformTypeIdentifiers

struct ProfileSettingsPane: View {
    @Environment(AppState.self) var appState
    @Environment(\.undoManager) private var undoManager
    let profileManager: ProfileManager

    @State private var newProfileName = ""
    @State private var isApplying = false
    @State private var editingProfileID: UUID?
    @State private var editingName = ""
    @State private var profileToDelete: UUID?
    @State private var errorMessage: String?
    @State private var previewedProfile: Profile?
    /// Compute with previewedProfile so drawing the popover does not re-read the bar.
    @State private var previewedDiff: ProfileLayoutDiff?

    var body: some View {
        ThawForm {
            ThawSection("Profiles") {
                profileList
                createProfileControls
            }

            if !profileManager.profiles.isEmpty {
                // An inline link distinguishes navigation from a settings group.
                HStack {
                    Text("Automatic switching by display or Space")
                        .font(ThawType.footnote)
                        .foregroundStyle(ThawInk.supporting)
                    Spacer()
                    Button("Automation") {
                        SettingsSearchNavigation.selectSidebarPane(.automation, navigationState: appState.navigationState)
                    }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.plain)
                }
            }
        }
        .errorAlert("Couldn’t complete the profile action", message: $errorMessage)
        .alert("Delete Profile?", item: $profileToDelete) { id in
            Button("Delete", role: .destructive) { deleteProfile(id: id) }
            Button("Cancel", role: .cancel) {}
        } message: { id in
            if let profile = profileManager.profiles.first(where: { $0.id == id }) {
                Text("“\(profile.name)” will be deleted. You can undo this with Command-Z.")
            }
        }
    }

    // MARK: - Profile List

    @ViewBuilder
    private var profileList: some View {
        if profileManager.profiles.isEmpty {
            ThawEmptyState(
                systemImage: "rectangle.stack",
                title: "No profiles yet",
                caption: "Name your current setup below and choose Save Current to keep it as a profile."
            )
        } else {
            ForEach(profileManager.profiles) { profile in
                profileRow(for: profile)
                    .contextMenu {
                        profileActions(for: profile)
                    }
            }
        }
    }

    /// The row's secondary actions, shared by its ⋯ menu and its context menu.
    @ViewBuilder
    private func profileActions(for profile: ProfileMetadata) -> some View {
        Button("Rename") {
            editingProfileID = profile.id
            editingName = profile.name
        }

        Button("Duplicate") {
            duplicateProfile(id: profile.id)
        }

        Button("Export…") {
            exportProfile(id: profile.id, name: profile.name)
        }

        Divider()

        Button("Delete", role: .destructive) {
            profileToDelete = profile.id
        }
    }

    private func profileRow(for profile: ProfileMetadata) -> some View {
        HStack(spacing: ThawSpacing.inset) {
            if editingProfileID == profile.id {
                TextField("Profile name", text: $editingName, onCommit: {
                    commitRename(id: profile.id)
                })
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

                Button("Done") {
                    commitRename(id: profile.id)
                }
                .buttonStyle(.settingsGlass)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                    .opacity(profile.id == profileManager.activeProfileID ? 1 : 0)

                Text(profile.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    previewProfile(id: profile.id)
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.settingsGlass)
                .help("Preview this profile’s saved layout and settings")
                .accessibilityLabel("Preview this profile’s saved layout and settings")
                .popover(
                    isPresented: Binding(
                        get: { previewedProfile?.id == profile.id },
                        set: { isPresented in
                            if !isPresented {
                                previewedProfile = nil
                            }
                        }
                    ),
                    arrowEdge: .bottom
                ) {
                    if let previewedProfile {
                        ProfilePreviewView(profile: previewedProfile, diff: previewedDiff)
                    }
                }

                Button("Apply") {
                    applyProfile(id: profile.id)
                }
                .buttonStyle(.settingsGlass)
                .disabled(isApplying || profile.id == profileManager.activeProfileID)

                ThawMenu(
                    primaryAction: {
                        updateProfile(id: profile.id, scope: .all)
                    },
                    content: {
                        // Keep secondary dates in the menu so the profile name leads the row.
                        Section {
                            Text("Created \(profile.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(ThawType.metric)
                            Text("Modified \(profile.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(ThawType.metric)
                        }
                        Divider()
                        Button("Save Current Into This Profile") {
                            updateProfile(id: profile.id, scope: .all)
                        }
                        Button("Save Layout Only") {
                            updateProfile(id: profile.id, scope: .layoutOnly)
                        }
                        Button("Save Configuration Only") {
                            updateProfile(id: profile.id, scope: .configurationOnly)
                        }
                        Divider()
                        Button("Save Configuration on All Profiles") {
                            updateConfigurationOnAllProfiles()
                        }
                    },
                    title: {
                        Text("Save Current")
                    }
                )
                .help("Save the current configuration into this profile")

                MoreActionsMenu(label: "More profile actions") {
                    profileActions(for: profile)
                }
            }
        }
    }

    // MARK: - Create Profile

    @ViewBuilder
    private var createProfileControls: some View {
        HStack(spacing: ThawSpacing.base) {
            TextField("New profile name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)
                .onSubmit {
                    createProfile()
                }

            Button("Save Current") {
                createProfile()
            }
            .buttonStyle(.settingsGlass)
            .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        HStack {
            Spacer()
            Button {
                importProfile()
            } label: {
                HStack(spacing: ThawSpacing.tight) {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 14, height: 14)
                    Text("Import Profiles…")
                }
            }
            .buttonStyle(.settingsGlass)

            if !profileManager.profiles.isEmpty {
                Button {
                    exportAllProfiles()
                } label: {
                    HStack(spacing: ThawSpacing.tight) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 14, height: 14)
                        Text("Export Profiles…")
                    }
                }
                .buttonStyle(.settingsGlass)
            }
        }
    }

    // MARK: - Actions

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let profileID = try profileManager.saveProfile(name: name, from: appState)
            profileManager.activeProfileID = profileID
            newProfileName = ""
            registerProfileUndo(
                .delete(id: profileID, wasActive: true),
                actionName: String(localized: "Create Profile"),
                manager: profileManager,
                undoManager: undoManager,
                errorBinding: $errorMessage
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func previewProfile(id: UUID) {
        do {
            let profile = try profileManager.loadProfile(id: id)
            previewedDiff = diff(for: profile)
            previewedProfile = profile
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Compute once at popover opening to avoid repeated item-cache and spacing-domain reads for a fixed preview.
    private func diff(for profile: Profile) -> ProfileLayoutDiff {
        var diff = ProfileLayoutDiff.between(
            current: profileManager.currentLayoutSnapshot(from: appState),
            profile: profile.menuBarLayout
        )
        diff.settingChanges = ProfileLayoutDiff.settingChanges(
            current: GeneralSettingsSnapshot.capture(from: appState.settings.general),
            profile: profile.generalSettings
        ) + ProfileLayoutDiff.settingChanges(
            current: AdvancedSettingsSnapshot.capture(from: appState.settings.advanced),
            profile: profile.advancedSettings
        )

        // Warn only if applying the profile's display spacing would relaunch apps.
        let offset = Int(profile.globalDisplayConfiguration.itemSpacingOffset.rounded())
        // The profile's own mode is the one in effect by the time its spacing is applied.
        let applyMode = profile.spacingApplyMode ?? appState.settings.displaySettings.spacingApplyMode
        if applyMode == .relaunchApps, !appState.spacingManager.isOnDisk(offset: offset) {
            diff.relaunchingSpacingOffset = offset
        }
        return diff
    }

    private func applyProfile(id: UUID) {
        isApplying = true
        Task {
            do {
                let profile = try profileManager.loadProfile(id: id)
                let previousID = profileManager.activeProfileID
                profileManager.activeProfileID = id
                profileManager.applyProfile(profile, to: appState, previousProfileID: previousID)
                // Wait for the layout task to complete before re-enabling.
                await profileManager.layoutTask?.value
                if profileManager.layoutDidNotRun {
                    errorMessage = String(
                        localized: "The profile's settings were applied, but its menu bar arrangement was not: \(Constants.displayName) is not managing the menu bar yet. Apply it again once the menu bar is under \(Constants.displayName)'s control."
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isApplying = false
        }
    }

    private func updateProfile(id: UUID, scope: ProfileManager.ProfileUpdateScope = .all) {
        do {
            let previous = try profileManager.loadProfile(id: id)
            try profileManager.updateProfile(id: id, scope: scope, appState: appState)
            let actionName = switch scope {
            case .all: String(localized: "Save Profile")
            case .layoutOnly: String(localized: "Save Layout")
            case .configurationOnly: String(localized: "Save Configuration")
            }
            registerProfileUndo(
                .replace([previous]),
                actionName: actionName,
                manager: profileManager,
                undoManager: undoManager,
                errorBinding: $errorMessage
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateConfigurationOnAllProfiles() {
        var failed = 0
        var previous: [Profile] = []
        for profile in profileManager.profiles {
            do {
                try previous.append(profileManager.loadProfile(id: profile.id))
                try profileManager.updateProfile(id: profile.id, scope: .configurationOnly, appState: appState)
            } catch {
                failed += 1
            }
        }
        if failed > 0 {
            errorMessage = String(localized: "Failed to update configuration on \(failed) profiles.")
        }
        if !previous.isEmpty {
            registerProfileUndo(
                .replace(previous),
                actionName: String(localized: "Save Configuration on All Profiles"),
                manager: profileManager,
                undoManager: undoManager,
                errorBinding: $errorMessage
            )
        }
    }

    private func commitRename(id: UUID) {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            editingProfileID = nil
            return
        }
        let previousName = profileManager.profiles.first { $0.id == id }?.name
        do {
            try profileManager.renameProfile(id: id, to: name)
            if let previousName, previousName != name {
                registerProfileUndo(
                    .rename(id: id, to: previousName),
                    actionName: String(localized: "Rename Profile"),
                    manager: profileManager,
                    undoManager: undoManager,
                    errorBinding: $errorMessage
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        editingProfileID = nil
    }

    private func duplicateProfile(id: UUID) {
        let profile = profileManager.profiles.first { $0.id == id }
        let name = (profile?.name ?? String(localized: "Profile")) + " " + String(localized: "Copy")
        let existingIDs = Set(profileManager.profiles.map(\.id))
        do {
            try profileManager.duplicateProfile(id: id, newName: name)
            if let created = profileManager.profiles.first(where: { !existingIDs.contains($0.id) }) {
                registerProfileUndo(
                    .delete(id: created.id, wasActive: false),
                    actionName: String(localized: "Duplicate Profile"),
                    manager: profileManager,
                    undoManager: undoManager,
                    errorBinding: $errorMessage
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProfile(id: UUID) {
        do {
            let profile = try profileManager.loadProfile(id: id)
            let index = profileManager.profiles.firstIndex { $0.id == id }
            let metadata = index.map { profileManager.profiles[$0] }
            let wasActive = profileManager.activeProfileID == id
            try profileManager.deleteProfile(id: id)
            if wasActive {
                profileManager.activeProfileID = nil
                appState.itemManager.clearActiveProfileLayout()
            }
            if let index, let metadata {
                registerProfileUndo(
                    .restore(profile: profile, metadata: metadata, at: index, wasActive: wasActive),
                    actionName: String(localized: "Delete Profile"),
                    manager: profileManager,
                    undoManager: undoManager,
                    errorBinding: $errorMessage
                )
            }
        } catch {
            errorMessage = error.localizedDescription
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
        }
    }

    private func exportAllProfiles() {
        guard let json = profileManager.exportAllProfiles() else {
            errorMessage = String(localized: "Failed to encode profiles for export.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(Constants.displayName) Profiles.json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try json.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
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
        }
    }
}

// MARK: - Undo

/// Value-based edits retain only the manager and profile data, allowing undo after pane teardown.
private enum ProfileUndoStep {
    /// Puts back a profile the user deleted, at its old manifest position.
    case restore(profile: Profile, metadata: ProfileMetadata, at: Int, wasActive: Bool)
    /// Removes a profile the user created or duplicated.
    case delete(id: UUID, wasActive: Bool)
    case rename(id: UUID, to: String)
    /// Writes saved profile values back after a save or overwrite.
    case replace([Profile])

    /// Returns the inverse step for redo registration.
    func apply(to manager: ProfileManager) throws -> ProfileUndoStep {
        switch self {
        case let .restore(profile, metadata, index, wasActive):
            try manager.restoreProfile(profile, metadata: metadata, at: index, wasActive: wasActive)
            return .delete(id: metadata.id, wasActive: wasActive)
        case let .delete(id, wasActive):
            let profile = try manager.loadProfile(id: id)
            guard let index = manager.profiles.firstIndex(where: { $0.id == id }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let metadata = manager.profiles[index]
            try manager.deleteProfile(id: id)
            if wasActive {
                manager.activeProfileID = nil
            }
            return .restore(profile: profile, metadata: metadata, at: index, wasActive: wasActive)
        case let .rename(id, to):
            let previousName = manager.profiles.first { $0.id == id }?.name ?? ""
            try manager.renameProfile(id: id, to: to)
            return .rename(id: id, to: previousName)
        case let .replace(profiles):
            let previous = try profiles.map { try manager.loadProfile(id: $0.id) }
            for profile in profiles {
                try manager.replaceProfile(profile)
            }
            return .replace(previous)
        }
    }
}

/// Register completed edits against the manager so undo survives pane teardown.
private func registerProfileUndo(
    _ step: ProfileUndoStep,
    actionName: String,
    manager: ProfileManager,
    undoManager: UndoManager?,
    errorBinding: Binding<String?>
) {
    guard let undoManager else { return }
    // The undo stack retains this handler; capture its manager weakly to avoid a cycle.
    undoManager.registerUndo(withTarget: manager) { [weak undoManager] target in
        performProfileUndo(
            step,
            actionName: actionName,
            manager: target,
            undoManager: undoManager,
            errorBinding: errorBinding
        )
    }
    undoManager.setActionName(actionName)
}

/// Registers the inverse step so the next redo restores the same edit.
private func performProfileUndo(
    _ step: ProfileUndoStep,
    actionName: String,
    manager: ProfileManager,
    undoManager: UndoManager?,
    errorBinding: Binding<String?>
) {
    do {
        let reverse = try step.apply(to: manager)
        undoManager?.registerUndo(withTarget: manager) { [weak undoManager] target in
            performProfileUndo(
                reverse,
                actionName: actionName,
                manager: target,
                undoManager: undoManager,
                errorBinding: errorBinding
            )
        }
        undoManager?.setActionName(actionName)
    } catch {
        errorBinding.wrappedValue = error.localizedDescription
    }
}
