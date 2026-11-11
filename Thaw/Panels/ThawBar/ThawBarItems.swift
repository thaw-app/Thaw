//
//  ThawBarItems.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import MenuBarModel

/// The items a Thaw Bar shows, shared by the bar and its Settings preview so the two can't drift.
@MainActor
enum ThawBarItems {
    /// A folder's members when one is open, otherwise the section's items without the apps you switched off.
    static func items(
        in section: MenuBarSection.Name,
        folderMembers: [String]? = nil,
        itemManager: MenuBarItemManager,
        switchedOff: Set<String>
    ) -> [MenuBarItem] {
        if let folderMembers {
            return folderMembers.compactMap { identifier in
                itemManager.managedItems.first {
                    $0.canonicalIdentifier == identifier
                }
            }
        }
        return UserSwitchedOffApps.excluding(itemManager.managedItems(for: section), switchedOff: switchedOff)
    }
}
