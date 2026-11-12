//
//  ProfileUndoStep.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Undo values preserve profile data and apply shortcuts after the settings pane is torn down.
enum ProfileUndoStep {
    /// Puts back a profile the user deleted, at its old manifest position.
    case restore(profile: Profile, metadata: ProfileMetadata, at: Int, wasActive: Bool, shortcut: Data? = nil)
    /// Removes a profile the user created or duplicated.
    case delete(id: UUID)
    case rename(id: UUID, to: String)
    /// Writes saved profile values back after a save or overwrite.
    case replace([Profile])

    /// Returns the inverse step for redo registration.
    func apply(to manager: ProfileManager) throws -> ProfileUndoStep {
        switch self {
        case let .restore(profile, metadata, index, wasActive, shortcut):
            try manager.restoreProfile(profile, metadata: metadata, at: index, wasActive: wasActive)
            if ProfileApplyShortcuts().adopt(shortcut, for: metadata.id) {
                manager.rebuildProfileHotkeys()
            }
            return .delete(id: metadata.id)
        case let .delete(id):
            let profile = try manager.loadProfile(id: id)
            guard let index = manager.profiles.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
            let metadata = manager.profiles[index]
            let wasActive = manager.activeProfileID == id
            let shortcut = ProfileApplyShortcuts().shortcut(for: id)
            try manager.deleteProfile(id: id)
            if wasActive {
                manager.activeProfileID = nil
                manager.appState?.itemManager.clearActiveProfileLayout()
            }
            return .restore(profile: profile, metadata: metadata, at: index, wasActive: wasActive, shortcut: shortcut)
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
