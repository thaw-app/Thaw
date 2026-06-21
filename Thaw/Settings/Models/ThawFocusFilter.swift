//
//  ThawFocusFilter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - ThawFocusModeStore

/// Resolves the app-defined "Focus mode" that triggers can match.
///
/// macOS does not expose which system Focus (Personal, Work, …) is active,
/// and only one `SetFocusFilterIntent` is allowed per app — Thaw already
/// uses it (`ThawFocusFilter` in FocusFilterIntent.swift) to apply a menu
/// bar profile when a Focus activates. Rather than add a second filter
/// (which macOS forbids), the "Focus mode" is taken to be the name of the
/// profile that Focus Filter requested: the user attaches the Thaw profile
/// filter to a Focus and picks, say, the "Work" profile, and a
/// `Focus mode is "Work"` trigger then matches while that Focus is active.
///
/// `ThawFocusFilter.perform` writes the requested profile id to this
/// UserDefaults key on activation and clears it on deactivation, so this
/// always reflects the currently requested profile.
enum ThawFocusModeStore {
    /// The UserDefaults key written by `ThawFocusFilter`.
    private static let requestedProfileKey = "FocusFilterRequestedProfileID"

    /// The active app-defined Focus mode (the requested profile's name), or
    /// `nil` when no Thaw Focus Filter is currently applied.
    static var activeMode: String? {
        guard
            let id = UserDefaults.standard.string(forKey: requestedProfileKey),
            !id.isEmpty
        else {
            return nil
        }
        return profileName(forID: id) ?? id
    }

    /// Resolves a profile id to its name from the on-disk profile manifest,
    /// matching how `ProfileEntityQuery` reads profiles.
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
