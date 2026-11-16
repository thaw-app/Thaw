//
//  ProfilePageAction.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawUI

/// One thing the Profiles page does with the profiles or the menu bar. The app runs it, for its
/// own Settings window or for the settings process.
enum ProfilePageAction: Codable {
    /// Saves the current setup as a new profile and makes it the active one.
    case create(name: String)
    /// Reads a profile and what applying it would change.
    case preview(id: UUID)
    case apply(id: UUID, spacingRelaunchApproved: Bool)
    /// Saves the current setup into a profile, whole or in part.
    case update(id: UUID, scope: ProfileManager.ProfileUpdateScope)
    case updateSettingsInEveryProfile
    case rename(id: UUID, name: String)
    case duplicate(id: UUID, name: String)
    case delete(id: UUID)
    /// Answers with one profile's export file, or with every profile's when id is nil.
    case export(id: UUID?)
    /// Adds the profiles in an export file's contents.
    case importFile(Data)
    case edit(ProfileListEdit)
    /// Sets or clears the shortcut that applies a profile. Only the settings process asks: the
    /// app's own page records into the hotkey itself.
    case shortcut(KeyCombination?, profile: UUID)
    /// Stands a profile's shortcut down while the settings process records a new one.
    case recordingShortcut(Bool, profile: UUID)
}

/// A change to what switches to a profile or how it keeps its layout, saved with the profile list.
enum ProfileListEdit: Codable, Equatable {
    case display(uuid: String?, name: String?, profile: UUID)
    case space(key: String?, name: String?, profile: UUID)
    case layoutBehavior(keepsChanges: Bool?, reappliesAtLaunch: Bool?, profile: UUID)

    /// Throws when the list could not be saved, so whoever asked can say so.
    func apply(to manager: ProfileManager) throws {
        switch self {
        case let .display(uuid, name, profile):
            manager.setAssociatedDisplay(uuid: uuid, displayName: name, forProfileID: profile)
        case let .space(key, name, profile):
            manager.setAssociatedSpace(key: key, spaceName: name, forProfileID: profile)
        case let .layoutBehavior(keepsChanges, reappliesAtLaunch, profile):
            manager.setLayoutBehavior(keepsChanges: keepsChanges, reappliesAtLaunch: reappliesAtLaunch, forProfileID: profile)
        }
        if let message = manager.takeManifestError() {
            throw ProfilePageFailure(message: message)
        }
    }
}

/// What an action leaves for the page.
struct ProfilePageOutcome: Codable {
    /// The Undo menu's words for the action, when it can be undone.
    var undoName: String?
    var preview: ProfilePreview?
    /// An export file's contents, for the page to write where the person chose.
    var exported: Data?
    /// What to tell the person about an action that went through.
    var notice: String?
}

/// A profile as saved, and what applying it would change.
struct ProfilePreview: Codable {
    var profile: Profile
    var diff: ProfileLayoutDiff
}

/// A failed action, in the words the page shows.
struct ProfilePageFailure: LocalizedError, Equatable {
    var message: String

    var errorDescription: String? {
        message
    }
}
