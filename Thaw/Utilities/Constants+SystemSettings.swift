//
//  Constants+SystemSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

extension Constants {
    /// Opens System Settings > Menu Bar.
    @MainActor
    static func openMenuBarSystemSettings() {
        if let menuBarSystemSettingsURL {
            NSWorkspace.shared.open(menuBarSystemSettingsURL)
        }
    }
}
