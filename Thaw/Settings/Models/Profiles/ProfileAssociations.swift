//
//  ProfileAssociations.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Keeps each display and each Space owned by at most one profile, on a list held in memory.
nonisolated enum ProfileAssociations {
    /// Gives the display to the profile, clearing it from any other profile that held it.
    static func assignDisplay(_ uuid: String?, name: String?, to profileID: UUID, in profiles: inout [ProfileMetadata]) {
        if let uuid {
            for index in profiles.indices where profiles[index].associatedDisplayUUID == uuid {
                profiles[index].associatedDisplayUUID = nil
                profiles[index].associatedDisplayName = nil
            }
        }
        if let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].associatedDisplayUUID = uuid
            profiles[index].associatedDisplayName = uuid != nil ? name : nil
        }
    }

    /// Gives the Space to the profile, clearing it from any other profile that held it.
    static func assignSpace(_ key: String?, name: String?, to profileID: UUID, in profiles: inout [ProfileMetadata]) {
        if let key {
            for index in profiles.indices where profiles[index].associatedSpaceKey == key {
                profiles[index].associatedSpaceKey = nil
                profiles[index].associatedSpaceName = nil
            }
        }
        if let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].associatedSpaceKey = key
            profiles[index].associatedSpaceName = key != nil ? name : nil
        }
    }
}
