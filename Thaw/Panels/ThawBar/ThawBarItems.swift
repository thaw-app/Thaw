//
//  ThawBarItems.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// The items a Thaw Bar shows, shared by the bar and its Settings preview so the two can't drift.
@MainActor
enum ThawBarItems {
    /// The items for the live app: what is switched off and what a stand-in replaces come from menuBarManager.
    static func items(
        in section: MenuBarSection.Name,
        folderMembers: [String]? = nil,
        itemManager: MenuBarItemManager,
        menuBarManager: MenuBarManager
    ) -> [MenuBarItem] {
        items(
            in: section,
            folderMembers: folderMembers,
            itemManager: itemManager,
            switchedOff: menuBarManager.nativeAppHidingExperiment.userSwitchedOffBundleIDs,
            replacedOriginals: menuBarManager.systemExtraTakeover.replacedOriginalIdentifiers
        )
    }

    /// A folder's members when one is open, otherwise the section's items without the apps you switched off.
    /// Either way without Apple's items in replacedOriginals, which a stand-in is shown for.
    static func items(
        in section: MenuBarSection.Name,
        folderMembers: [String]? = nil,
        itemManager: MenuBarItemManager,
        switchedOff: Set<String>,
        replacedOriginals: Set<String>
    ) -> [MenuBarItem] {
        if let folderMembers {
            let members = folderMembers.compactMap { identifier in
                itemManager.managedItems.first {
                    $0.canonicalIdentifier == identifier
                }
            }
            return ReplacedOriginals.excluding(members, replaced: replacedOriginals)
        }
        let listed = UserSwitchedOffApps.excluding(itemManager.managedItems(for: section), switchedOff: switchedOff)
        return ReplacedOriginals.excluding(listed, replaced: replacedOriginals)
    }
}
