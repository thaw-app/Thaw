//
//  LayoutDisplayedItems.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
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
        DisplayedItemInventory.cache(appState: appState, runningApplications: runningApplications)
            .managedItems(for: section)
            // Thaw Bar Only items have their own row.
            // A switched-off Thaw icon stays registered at zero width so it can
            // return in place, but it is not on the bar, so it gets no slot.
            .filter { appState.settings.general.showThawIcon || !$0.tag.matchesVisibleControlItem }
    }

    /// The items the reorder editor lists for a section: those a drag may pick up, each once.
    /// The same item can be read twice; the leftmost one is kept, as in the Layout bars.
    static func editorItems(
        in section: MenuBarSection.Name,
        appState: AppState,
        runningApplications: [NSRunningApplication]
    ) -> [MenuBarItem] {
        items(in: section, appState: appState, runningApplications: runningApplications)
            .filter(LayoutBarPaddingView.acceptsLayoutDrag(of:))
            .uniqued(on: \.uniqueIdentifier)
    }
}
