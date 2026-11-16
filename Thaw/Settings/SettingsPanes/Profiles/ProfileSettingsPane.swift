//
//  ProfileSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI
import UniformTypeIdentifiers

struct ProfileSettingsPane: View {
    @Environment(AppState.self) var appState
    @Environment(\.undoManager) private var undoManager
    let profileManager: ProfileManager

    /// Where the page asks for a file to export to or import from. Tests replace these so no panel opens.
    var fileChoosers = FileChoosers()
    /// Set in the settings process, where the app runs the page's actions.
    var remote: SettingsRemote? = .current

    @State private var newProfileName = ""
    @State private var isApplying = false
    @State private var editingProfileID: UUID?
    @State private var editingName = ""
    @State private var profileToDelete: UUID?
    @State private var errorMessage: String?
    @State private var previewedProfile: Profile?
    /// Computed with previewedProfile when the selection changes, so drawing
    /// the page does not re-read the bar.
    @State private var previewedDiff: ProfileLayoutDiff?
    /// Until the first preview has come, which in the settings process the app sends.
    @State private var awaitsPreview = true
    @State private var selectedProfileID: UUID?
    @FocusState private var isListFocused: Bool

    /// The profile whose details show under the list: the one picked, else
    /// the active one, else the first.
    private var selectedProfile: ProfileMetadata? {
        let profiles = profileManager.profiles
        return profiles.first { $0.id == selectedProfileID }
            ?? profiles.first { $0.id == profileManager.activeProfileID }
            ?? profiles.first
    }

    var body: some View {
        ThawForm {
            ThawSection {
                Text("Profiles")
            } content: {
                profileList
                createProfileControls
            } footer: {
                if !profileManager.profiles.isEmpty {
                    Text(AutomationSummary.profileSwitching(AutomationSummary.assignments(of: profileManager.profiles)))
                        .font(ThawType.footnote)
                        .foregroundStyle(ThawInk.supporting)
                }
            }

            if let selected = selectedProfile {
                ProfileSwitchesSection(
                    profileManager: profileManager,
                    displaySettings: appState.settings.displaySettings,
                    profile: selected,
                    errorMessage: $errorMessage,
                    remote: remote
                )
                ProfileLayoutBehaviorSection(
                    profileManager: profileManager,
                    profile: selected,
                    errorMessage: $errorMessage,
                    remote: remote
                )
                ProfileChangesSection(
                    profile: previewedProfile,
                    diff: previewedDiff,
                    awaitsPreview: awaitsPreview,
                    update: { updateProfile(id: selected.id, scope: $0) },
                    updateAll: updateConfigurationOnAllProfiles
                )
            }
        }
        .onChange(of: selectedProfile?.id, initial: true) { _, id in
            if let id {
                previewProfile(id: id)
            }
        }
        .errorAlert("Couldn’t complete the profile action", message: $errorMessage)
        .alert("Delete Profile?", item: $profileToDelete) { id in
            Button("Delete", role: .destructive) { deleteProfile(id: id) }
            Button("Cancel", role: .cancel) { /* The alert dismisses itself; cancelling needs no other work. */ }
        } message: { id in
            if let profile = profileManager.profiles.first(where: { $0.id == id }) {
                Text("“\(profile.name)” will be deleted. If its saved content is available, you can undo this with Command-Z.")
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
            // One block of rows drawn like the sidebar's, so picking a
            // profile looks like picking a page, and the arrow keys step
            // through it once it has focus.
            VStack(spacing: ThawSpacing.hairline) {
                ForEach(profileManager.profiles) { profile in
                    profileRow(for: profile)
                        .contextMenu {
                            profileActions(for: profile)
                        }
                }
            }
            .thawKeyboardList(isFocused: $isListFocused) { direction in
                let ids = profileManager.profiles.map(\.id)
                if let next = ProfileListStep.profile(after: selectedProfile?.id, in: ids, moving: direction) {
                    selectedProfileID = next
                }
            }
            .listRowInsets(EdgeInsets(top: ThawSpacing.tight, leading: ThawSpacing.tight, bottom: ThawSpacing.tight, trailing: ThawSpacing.tight))
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
        ProfileListRow(
            profile: profile,
            isSelected: profile.id == selectedProfile?.id,
            showsFocus: isListFocused,
            isActive: profile.id == profileManager.activeProfileID,
            isApplying: isApplying,
            isEditing: editingProfileID == profile.id,
            editingName: $editingName,
            select: { selectedProfileID = profile.id },
            apply: { applyProfile(id: profile.id) },
            commitRename: { commitRename(id: profile.id) },
            actions: { profileActions(for: profile) }
        )
    }

    /// Reads the selected profile again after it or the bar changed, so its
    /// "Applying this profile changes" section stays true.
    private func refreshPreview() {
        if let id = selectedProfile?.id {
            previewProfile(id: id)
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

    private var runner: ProfilePageRunner {
        ProfilePageRunner(
            performer: ProfilePagePerformer(profileManager: profileManager, appState: appState),
            remote: remote,
            undoManager: undoManager,
            errorMessage: $errorMessage
        )
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        runner.run(.create(name: name)) { outcome in
            if outcome != nil {
                newProfileName = ""
            }
        }
    }

    private func previewProfile(id: UUID) {
        runner.run(.preview(id: id)) { outcome in
            awaitsPreview = false
            // An answer from the app may arrive after another profile was picked.
            guard let preview = outcome?.preview, preview.profile.id == selectedProfile?.id else { return }
            previewedDiff = preview.diff
            previewedProfile = preview.profile
        }
    }

    private func applyProfile(id: UUID) {
        isApplying = true
        // What the apply would change says whether it restarts apps, which may need a yes first.
        runner.run(.preview(id: id)) { outcome in
            guard let preview = outcome?.preview else {
                isApplying = false
                return
            }
            runner.run(.apply(id: id, spacingRelaunchApproved: approvesSpacingRelaunch(for: preview))) { outcome in
                // The layout has run by now, so the Apply buttons stayed off until it ended.
                isApplying = false
                showResult(of: outcome)
            }
        }
    }

    /// After an action that changed a profile or the bar: shows the selected profile's changes
    /// again, and what the action has to say.
    private func showResult(of outcome: ProfilePageOutcome?) {
        guard let outcome else { return }
        refreshPreview()
        if let notice = outcome.notice {
            errorMessage = notice
        }
    }

    private func updateProfile(id: UUID, scope: ProfileManager.ProfileUpdateScope = .all) {
        runner.run(.update(id: id, scope: scope), then: showResult)
    }

    private func updateConfigurationOnAllProfiles() {
        runner.run(.updateSettingsInEveryProfile, then: showResult)
    }

    private func commitRename(id: UUID) {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            runner.run(.rename(id: id, name: name))
        }
        editingProfileID = nil
    }

    private func duplicateProfile(id: UUID) {
        let profile = profileManager.profiles.first { $0.id == id }
        let name = (profile?.name ?? String(localized: "Profile")) + " " + String(localized: "Copy")
        runner.run(.duplicate(id: id, name: name))
    }

    private func deleteProfile(id: UUID) {
        runner.run(.delete(id: id))
    }

    private func exportProfile(id: UUID, name: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        guard let url = fileChoosers.save("\(safeName).json") else { return }
        runner.run(.export(id: id)) { write($0, to: url) }
    }

    private func exportAllProfiles() {
        runner.run(.export(id: nil)) { outcome in
            guard outcome != nil, let url = fileChoosers.save("\(Constants.displayName) Profiles.json") else { return }
            write(outcome, to: url)
        }
    }

    /// Writes an export where the person chose, from the process whose panel they chose it in.
    private func write(_ outcome: ProfilePageOutcome?, to url: URL) {
        guard let outcome, let exported = outcome.exported else { return }
        do {
            try exported.write(to: url, options: .atomic)
            if let notice = outcome.notice {
                errorMessage = notice
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importProfile() {
        guard let url = fileChoosers.open() else { return }
        do {
            try runner.run(.importFile(Data(contentsOf: url)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
