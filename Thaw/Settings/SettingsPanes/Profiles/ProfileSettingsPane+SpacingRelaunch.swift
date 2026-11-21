//
//  ProfileSettingsPane+SpacingRelaunch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension ProfileSettingsPane {
    /// Asks before the apply restarts apps when the user chose to be asked; without a yes, spacing is only saved.
    func approvesSpacingRelaunch(for preview: ProfilePreview) -> Bool {
        let displaySettings = appState.settings.displaySettings
        guard
            preview.diff.relaunchingSpacingOffset != nil,
            ProfileRelaunchSafety.needsConfirmation(for: preview.profile, displaySettings: displaySettings)
        else {
            return false
        }
        return displaySettings.presentSpacingRelaunchConfirmation()
    }
}
