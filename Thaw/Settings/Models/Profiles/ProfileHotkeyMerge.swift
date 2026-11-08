//
//  ProfileHotkeyMerge.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// The shortcuts a profile leaves in place when applied.
nonisolated enum ProfileHotkeyMerge {
    /// The profile's shortcut for each action it knew, set or cleared; any
    /// other action keeps its current one. A profile saved before it recorded
    /// its actions only sets the shortcuts it stores, since a missing entry
    /// can't tell a cleared shortcut from a newer action.
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
