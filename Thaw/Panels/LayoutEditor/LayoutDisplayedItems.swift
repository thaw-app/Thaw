//
//  LayoutDisplayedItems.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// The items a layout editor shows for one section, in display order.
@MainActor
enum LayoutDisplayedItems {
    static func items(
        in section: MenuBarSection.Name,
        appState: AppState,
        runningApplications: [NSRunningApplication]
    ) -> [MenuBarItem] {
        // Section membership is authored state, not evidence of a physical move:
        // project the inventory without publishing stale geometry to the manager.
        MenuBarBackendProvider.current.rebucket(
            appState.itemManager.itemCache,
            hider: appState.menuBarManager.sectionController,
            allowsAlwaysHidden: appState.settings.advanced.enableAlwaysHiddenSection
        ).retainingRunningOwners(
            processIDs: Set(runningApplications.map(\.processIdentifier)),
            bundleIdentifiers: Set(runningApplications.compactMap(\.bundleIdentifier))
        ).orderingOverflowStack(savedOrder: appState.itemManager.savedSectionOrder).managedItems(for: section)
            // Thaw Bar Only items have their own row.
            .filter { !appState.itemManager.isThawBarOnly($0) }
            // A switched-off Thaw icon stays registered at zero width so it can
            // return in place, but it is not on the bar, so it gets no slot.
            .filter { appState.settings.general.showThawIcon || !$0.tag.matchesVisibleControlItem }
    }
}
