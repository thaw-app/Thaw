//
//  AutomaticProfileChoice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Which profile switches in when no Focus profile is in charge, at launch and when a Focus ends:
/// the current Space's profile wins over the display's.
nonisolated enum AutomaticProfileChoice: Equatable {
    case space(key: String)
    case display(uuid: String)
    case none

    static func choose(spaceKey: String?, spaceHasProfile: (String) -> Bool, displayUUID: String?) -> Self {
        if let spaceKey, spaceHasProfile(spaceKey) {
            return .space(key: spaceKey)
        }
        if let displayUUID {
            return .display(uuid: displayUUID)
        }
        return .none
    }
}
