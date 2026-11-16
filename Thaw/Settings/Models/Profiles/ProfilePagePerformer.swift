//
//  ProfilePagePerformer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Runs the Profiles page's actions on the profiles and the menu bar, in the app.
@MainActor
struct ProfilePagePerformer {
    let profileManager: ProfileManager
    let appState: AppState

    /// What an action left, with what only the app can use: the step that undoes it and, for an
    /// apply, the wait for its layout.
    struct Done {
        var outcome = ProfilePageOutcome()
        var undo: ProfileUndoStep?
        /// Ends when the apply's layout has, with what to say when only its settings went through.
        var applying: Task<ProfilePageOutcome, Never>?

        init(outcome: ProfilePageOutcome = ProfilePageOutcome()) {
            self.outcome = outcome
        }

        init(undo: ProfileUndoStep, named name: String) {
            outcome.undoName = name
            self.undo = undo
        }
    }

    func perform(_ action: ProfilePageAction) throws -> Done {
        switch action {
        case let .create(name):
            return try create(name: name)
        case let .preview(id):
            let profile = try profileManager.loadProfile(id: id)
            return Done(outcome: ProfilePageOutcome(preview: ProfilePreview(profile: profile, diff: diff(for: profile))))
        case let .apply(id, spacingRelaunchApproved):
            return try apply(id: id, spacingRelaunchApproved: spacingRelaunchApproved)
        case let .update(id, scope):
            return try update(id: id, scope: scope)
        case .updateSettingsInEveryProfile:
            return updateSettingsInEveryProfile()
        case let .rename(id, name):
            return try rename(id: id, to: name)
        case let .duplicate(id, name):
            return try duplicate(id: id, name: name)
        case let .delete(id):
            return try delete(id: id)
        case .export, .importFile, .edit:
            return try Done(outcome: performWithoutUndo(action))
        }
    }

    /// The actions the page has no undo for: files and what switches to a profile.
    private func performWithoutUndo(_ action: ProfilePageAction) throws -> ProfilePageOutcome {
        switch action {
        case let .export(id):
            return try export(id: id)
        case let .importFile(contents):
            try throughTemporaryFile { file in
                try contents.write(to: file)
                try profileManager.importProfile(from: file)
            }
        case let .edit(edit):
            try edit.apply(to: profileManager)
        default:
            break
        }
        return ProfilePageOutcome()
    }

    /// What applying the profile would change on the bar and in the settings as they are now.
    func diff(for profile: Profile) -> ProfileLayoutDiff {
        var diff = ProfileLayoutDiff.between(
            current: profileManager.currentLayoutSnapshot(from: appState),
            profile: profile.menuBarLayout
        )
        diff.settingChanges = ProfilePreviewChanges.settingChanges(of: profile, appState: appState)

        // Warn only if the spacing the apply leaves on the menu bar's display would relaunch apps.
        let offset = ProfileRelaunchSafety.spacingOffset(of: profile, activeDisplayUUID: appState.settings.displaySettings.activeMenuBarDisplayUUID)
        // The mode in effect once the profile is applied, merged the way the apply merges it.
        let applyMode = ProfileRelaunchSafety.merged(profile, onto: appState.settings.displaySettings).applyMode
        if applyMode == .relaunchApps, !appState.spacingManager.isOnDisk(offset: offset) {
            diff.relaunchingSpacingOffset = offset
        }
        return diff
    }

    private func create(name: String) throws -> Done {
        let id = try profileManager.saveProfile(name: name, from: appState)
        profileManager.activeProfileID = id
        return Done(undo: .delete(id: id), named: String(localized: "Create Profile"))
    }

    private func apply(id: UUID, spacingRelaunchApproved: Bool) throws -> Done {
        try profileManager.switchToProfile(id: id, on: appState, spacingRelaunchApproved: spacingRelaunchApproved)
        var done = Done()
        // This apply's own layout: a later apply replaces the manager's task.
        done.applying = Task { [profileManager, layout = profileManager.layoutTask] in
            await layout?.value
            guard profileManager.layoutDidNotRun else { return ProfilePageOutcome() }
            return ProfilePageOutcome(notice: String(
                localized: "The profile's settings were applied, but its menu bar arrangement was not: \(Constants.displayName) is not managing the menu bar yet. Apply it again once the menu bar is under \(Constants.displayName)'s control."
            ))
        }
        return done
    }

    private func update(id: UUID, scope: ProfileManager.ProfileUpdateScope) throws -> Done {
        let previous = try profileManager.loadProfile(id: id)
        try profileManager.updateProfile(id: id, scope: scope, appState: appState)
        let name = switch scope {
        case .all: String(localized: "Save Profile")
        case .layoutOnly: String(localized: "Save Layout")
        case .configurationOnly: String(localized: "Save Configuration")
        }
        return Done(undo: .replace([previous]), named: name)
    }

    private func updateSettingsInEveryProfile() -> Done {
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
        var done = previous.isEmpty ? Done() : Done(undo: .replace(previous), named: String(localized: "Save Configuration on All Profiles"))
        if failed > 0 {
            done.outcome.notice = String(localized: "Failed to update configuration on \(failed) profiles.")
        }
        return done
    }

    private func rename(id: UUID, to name: String) throws -> Done {
        let previousName = profileManager.profiles.first { $0.id == id }?.name
        try profileManager.renameProfile(id: id, to: name)
        guard let previousName, previousName != name else { return Done() }
        return Done(undo: .rename(id: id, to: previousName), named: String(localized: "Rename Profile"))
    }

    private func duplicate(id: UUID, name: String) throws -> Done {
        let existingIDs = Set(profileManager.profiles.map(\.id))
        try profileManager.duplicateProfile(id: id, newName: name)
        guard let created = profileManager.profiles.first(where: { !existingIDs.contains($0.id) }) else { return Done() }
        return Done(undo: .delete(id: created.id), named: String(localized: "Duplicate Profile"))
    }

    private func delete(id: UUID) throws -> Done {
        let (profile, shortcut) = (try ProfileDeletion.snapshotForUndo { try profileManager.loadProfile(id: id) }, ProfileApplyShortcuts().shortcut(for: id))
        let index = profileManager.profiles.firstIndex { $0.id == id }
        let metadata = index.map { profileManager.profiles[$0] }
        let wasActive = profileManager.activeProfileID == id
        try profileManager.deleteProfile(id: id)
        if wasActive {
            profileManager.activeProfileID = nil
            appState.itemManager.clearActiveProfileLayout()
        }
        guard let profile, let index, let metadata else { return Done() }
        return Done(
            undo: .restore(profile: profile, metadata: metadata, at: index, wasActive: wasActive, shortcut: shortcut),
            named: String(localized: "Delete Profile")
        )
    }

    private func export(id: UUID?) throws -> ProfilePageOutcome {
        guard let id else {
            let (json, unreadable) = profileManager.exportAllProfiles()
            guard let json else {
                throw ProfilePageFailure(message: String(localized: "Failed to encode profiles for export."))
            }
            let notice = unreadable.isEmpty
                ? nil
                : String(localized: "Exported, except profiles that couldn't be read: \(unreadable.formatted(.list(type: .and)))")
            return ProfilePageOutcome(exported: Data(json.utf8), notice: notice)
        }
        return try throughTemporaryFile { file in
            try profileManager.exportProfile(id: id, to: file)
            return try ProfilePageOutcome(exported: Data(contentsOf: file))
        }
    }

    /// The profile store exports to a file and imports from one, while the page deals in the
    /// file's contents: a file the person chose may only be open to the process that asked them.
    private func throughTemporaryFile<Value>(_ body: (URL) throws -> Value) throws -> Value {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        return try body(file)
    }
}
