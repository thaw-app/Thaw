//
//  DisplayedItemInventory.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// The inventory every item list shows: the Layout bars and editor, and the Search panel.
@MainActor
enum DisplayedItemInventory {
    /// The item cache projected onto the current section assignments, minus apps that quit, in saved
    /// order. Membership is authored state, not a physical move, so nothing is published to the manager.
    static func cache(appState: AppState, runningApplications: [NSRunningApplication]) -> MenuBarItemCache {
        MenuBarBackendProvider.current.rebucket(
            appState.itemManager.itemCache,
            hider: appState.menuBarManager.sectionController,
            allowsAlwaysHidden: appState.settings.advanced.enableAlwaysHiddenSection
        ).retainingRunningOwners(
            processIDs: Set(runningApplications.map(\.processIdentifier)),
            bundleIdentifiers: Set(runningApplications.compactMap(\.bundleIdentifier))
        ).orderingOverflowStack(savedOrder: appState.itemManager.savedSectionOrder)
    }

    /// The same projection for the apps running now.
    static func cache(appState: AppState) -> MenuBarItemCache {
        cache(appState: appState, runningApplications: NSWorkspace.shared.runningApplications.filter { !$0.isTerminated })
    }
}
