//
//  ProfileHotkeyMerge.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// The shortcuts a profile leaves in place when applied.
nonisolated enum ProfileHotkeyMerge {
    /// Sets or clears only the actions the profile knew; others keep their shortcut. An
    /// older profile only sets what it stores: a missing entry may be a newer action.
    static func merged(current: [String: Data], profile: [String: Data], knownActions: [String]?) -> [String: Data] {
        var merged = current
        for action in knownActions ?? Array(profile.keys) {
            merged[action] = profile[action]
        }
        return merged
    }

    /// The actions a profile saved now knows.
    @MainActor
    static var currentActions: [String] {
        HotkeyAction.settingsActions.map(\.rawValue)
    }
}
