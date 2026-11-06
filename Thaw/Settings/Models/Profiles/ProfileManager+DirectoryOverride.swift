//
//  ProfileManager+DirectoryOverride.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension ProfileManager {
    /// Where a manager made without a directory keeps its profiles, when set. Tests scope a
    /// temporary folder here so an AppState they make never touches the user's profiles.
    @TaskLocal static var directoryOverride: URL?
}
