//
//  ThawFocusModeStore.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Read-side view of the Focus mode requested by ``ThawFocusFilter``.
///
/// Profile-specific Focus Filter triggers need the requested Thaw profile by
/// name. The Focus Filter API does not expose the enclosing macOS Focus's
/// display name, so the UI deliberately describes this value as a profile.
nonisolated enum ThawFocusModeStore {
    /// The active Focus Filter's requested Thaw profile name, or
    /// `nil` when no Thaw Focus Filter is currently applied.
    static var activeMode: String? {
        guard
            let id = Defaults.string(forKey: .focusFilterRequestedProfileID),
            !id.isEmpty
        else {
            return nil
        }
        return profileName(forID: id) ?? id
    }

    /// Resolves a profile id to its name from the on-disk profile manifest,
    /// matching how ``ProfileEntityQuery`` reads profiles.
    private static func profileName(forID id: String) -> String? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let manifestURL = appSupport.appendingPathComponent("Thaw/Profiles/profiles.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifests = try? decoder.decode([ProfileMetadata].self, from: data) else {
            return nil
        }
        return manifests.first { $0.id.uuidString == id }?.name
    }
}
