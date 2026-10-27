//
//  ProfileSettingsPane+SpacingRelaunch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension ProfileSettingsPane {
    /// Asks before the apply restarts apps when the user chose to be asked; without a yes, spacing is only saved.
    func approvesSpacingRelaunch(forProfileID id: UUID) throws -> Bool {
        let profile = try profileManager.loadProfile(id: id)
        let displaySettings = appState.settings.displaySettings
        guard
            diff(for: profile).relaunchingSpacingOffset != nil,
            ProfileRelaunchSafety.needsConfirmation(for: profile, displaySettings: displaySettings)
        else {
            return false
        }
        return displaySettings.presentSpacingRelaunchConfirmation()
    }
}
