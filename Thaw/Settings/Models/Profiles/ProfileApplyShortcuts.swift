//
//  ProfileApplyShortcuts.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// The shortcut that applies each profile, stored apart from the profile files
/// under ProfileHotkeys, keyed by profile ID.
nonisolated struct ProfileApplyShortcuts {
    var defaults: UserDefaults = Defaults.store

    private var stored: [String: Data] {
        defaults.dictionary(forKey: Defaults.Key.profileHotkeys.rawValue) as? [String: Data] ?? [:]
    }

    func shortcut(for profileID: UUID) -> Data? {
        stored[profileID.uuidString]
    }

    /// Gives an imported profile its shortcut, unless another profile already
    /// uses it: one shortcut can only apply one profile. Returns whether it was set.
    @discardableResult
    func adopt(_ shortcut: Data?, for profileID: UUID) -> Bool {
        guard let shortcut, !stored.values.contains(shortcut) else {
            return false
        }
        var updated = stored
        updated[profileID.uuidString] = shortcut
        defaults.set(updated, forKey: Defaults.Key.profileHotkeys.rawValue)
        return true
    }
}
