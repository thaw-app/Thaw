//
//  ProfileExport.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - ProfileExportEntry

/// A single profile bundled with its metadata for export/import.
/// Preserves display associations that live on the manifest.
nonisolated struct ProfileExportEntry: Codable {
    var profile: Profile
    var associatedDisplayUUID: String?
    var associatedDisplayName: String?
    /// Space associations are exported too, but a key from another Mac will
    /// never match locally, so importing one is harmless rather than useful.
    var associatedSpaceKey: String?
    var associatedSpaceName: String?
    /// The profile's layout switches. Nil in files exported before them.
    var keepsLayoutChanges: Bool?
    var reappliesAtLaunch: Bool?
    /// The encoded shortcut that applies the profile. Nil in older files and without one.
    var applyShortcut: Data?
}

/// Wrapper for exporting multiple profiles as a single file.
nonisolated struct ProfileExportBundle: Codable {
    var version: Int = 1
    var entries: [ProfileExportEntry]
}
