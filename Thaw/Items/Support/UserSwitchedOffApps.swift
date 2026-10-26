//
//  UserSwitchedOffApps.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Apps the user switched off in System Settings › Menu Bar › Allow in the Menu Bar. macOS still
/// reports their items, parked off the bar, but never draws them, so the Thaw Bar leaves them out.
/// Apps that Native hiding switched off are in Thaw's record and stay.
nonisolated enum UserSwitchedOffApps {
    /// The switched-off apps that are the user's choice. Thaw's own items are kept off the system
    /// list on purpose, so they never count.
    static func bundleIDs(switchedOff: [String], ownedByThaw: (String) -> Bool) -> Set<String> {
        Set(switchedOff.filter { !ownedByThaw($0) })
    }

    /// The apps that own these items, by bundle identifier.
    static func bundleIDs(of items: [MenuBarItem]) -> Set<String> {
        Set(items.compactMap { item in
            guard case let .string(bundleID) = item.tag.namespace else { return nil }
            return bundleID
        })
    }

    /// The items to show, in their order, without those of switched-off apps.
    static func excluding(_ items: [MenuBarItem], switchedOff: Set<String>) -> [MenuBarItem] {
        guard !switchedOff.isEmpty else { return items }
        return items.filter { item in
            guard case let .string(bundleID) = item.tag.namespace else { return true }
            return !switchedOff.contains(bundleID)
        }
    }
}
