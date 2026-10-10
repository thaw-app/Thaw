//
//  MenuBarItemManager+SplitApps.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

// MARK: - Split Apps

extension MenuBarItemManager {
    /// The concealed section an item's app pulls it into, or nil when the
    /// item is shown or its app is not split.
    func sectionHidingItemWithItsApp(_ item: MenuBarItem, appState: AppState) -> MenuBarSection.Name? {
        let controller = appState.menuBarManager.sectionController
        guard controller.authoredSection(for: item.uniqueIdentifier) == .visible else { return nil }
        return AppSiblingSections.concealingSiblingSection(
            of: item,
            among: itemCache.managedItems,
            section: { controller.authoredSection(for: $0.uniqueIdentifier) }
        )
    }

    /// Every item of item's app, so the app can be moved as one.
    func appItems(for item: MenuBarItem) -> [MenuBarItem] {
        itemCache.managedItems.filter {
            $0.tag.namespace == item.tag.namespace && MenuBarItemGrouping.isGroupable($0.tag)
        }
    }
}
