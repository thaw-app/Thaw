//
//  ThawFocusModeStore.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import os.lock

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

    /// The profile manifest, shared with ``ProfileEntityQuery``.
    ///
    /// Centralized here so the path is stated once rather than rebuilt at
    /// each call site.
    static var manifestURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Thaw/Profiles/profiles.json")
    }

    /// Names by profile id, with the manifest's modification date at the time
    /// it was parsed.
    private struct CachedManifest {
        var modificationDate: Date?
        var namesByID: [String: String]
    }

    private static let cache = OSAllocatedUnfairLock<CachedManifest?>(initialState: nil)

    /// Resolves a profile id to its name from the on-disk profile manifest,
    /// matching how ``ProfileEntityQuery`` reads profiles.
    ///
    /// Cached against the manifest's modification date. ``activeMode`` is
    /// sampled on the trigger poll every five seconds, and re-reading and
    /// re-decoding the whole manifest each time is pure waste when it changes
    /// only on a profile edit. `stat` is cheap; the read and the JSON decode
    /// are not.
    private static func profileName(forID id: String) -> String? {
        guard let manifestURL else { return nil }

        let modificationDate = (
            try? FileManager.default.attributesOfItem(atPath: manifestURL.path)[.modificationDate]
        ) as? Date

        return cache.withLock { cached in
            if let cached, cached.modificationDate == modificationDate {
                return cached.namesByID[id]
            }
            guard let data = try? Data(contentsOf: manifestURL) else {
                // Cache the miss too, so a missing manifest does not retry the
                // read on every poll.
                cached = CachedManifest(modificationDate: modificationDate, namesByID: [:])
                return nil
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let namesByID: [String: String] =
                if let manifests = try? decoder.decode([ProfileMetadata].self, from: data) {
                    Dictionary(
                        manifests.map { ($0.id.uuidString, $0.name) },
                        uniquingKeysWith: { first, _ in first }
                    )
                } else {
                    [:]
                }
            cached = CachedManifest(modificationDate: modificationDate, namesByID: namesByID)
            return namesByID[id]
        }
    }
}
