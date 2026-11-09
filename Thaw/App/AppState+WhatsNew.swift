//
//  AppState+WhatsNew.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

extension AppState {
    /// Read from Defaults, not the Privacy model: What's New asks during launch,
    /// before the model loads its stored values.
    static var storedShowReleaseNotesAfterUpdate: Bool {
        Defaults.bool(forKey: .showReleaseNotesAfterUpdate)
    }

    /// Read from Defaults for the same launch-order reason.
    static var storedFetchReleaseNotes: Bool {
        Defaults.bool(forKey: .fetchReleaseNotes)
    }
}
