//
//  DisplayProfileResolution.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Which profile a settled display change asks for. A Focus filter's profile and a Space's own profile
/// outrank the display's, and a change that leaves the menu bar on the same display switches nothing,
/// so a profile picked by hand survives a new resolution or arrangement.
nonisolated enum DisplayProfileResolution {
    struct Situation: Equatable {
        /// The display that owns the menu bar once the change settled.
        var displayUUID: String?
        /// The display that owned it at the change resolved before this one.
        var previousDisplayUUID: String?
        var activeSpaceKey: String?
        var focusFilterActive = false
        var activeProfileID: UUID?
    }

    /// The profile to apply, or nil to leave the active one in place.
    static func resolve(_ situation: Situation, profiles: [ProfileMetadata]) -> UUID? {
        guard let display = situation.displayUUID, display != situation.previousDisplayUUID, !situation.focusFilterActive
        else { return nil }
        if let spaceKey = situation.activeSpaceKey, profiles.contains(where: { $0.associatedSpaceKey == spaceKey }) {
            return nil
        }
        guard let match = profiles.first(where: { $0.associatedDisplayUUID == display }), match.id != situation.activeProfileID
        else { return nil }
        return match.id
    }
}
