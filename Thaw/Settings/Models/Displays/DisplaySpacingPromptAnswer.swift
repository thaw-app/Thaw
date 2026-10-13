//
//  DisplaySpacingPromptAnswer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension DisplaySettingsManager {
    /// Makes a "Don't ask again" answer to the spacing prompt stick.
    ///
    /// Apply turns confirmations off. Cancel switches to writeOnly, so later
    /// display changes relaunch nothing and have nothing to ask about; turning
    /// confirmations off there would relaunch apps unasked next time.
    func rememberSpacingRelaunchAnswer(approved: Bool) {
        if approved {
            confirmSpacingRelaunch = false
        } else {
            spacingApplyMode = .writeOnly
        }
    }
}
