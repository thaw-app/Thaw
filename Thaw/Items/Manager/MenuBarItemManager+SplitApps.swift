//
//  MenuBarItemManager+SplitApps.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

// MARK: - Split Apps

extension MenuBarItemManager {
    /// Where macOS puts an item of a split app under the hiding that is
    /// running, or nil when its section in Layout holds.
    func appWideOverride(for item: MenuBarItem, appState: AppState) -> AppWideOverride? {
        let menuBarManager = appState.menuBarManager
        let controller = menuBarManager.sectionController
        return AppSiblingSections.appWideOverride(
            of: item,
            among: itemCache.managedItems,
            rule: AppWideHidingRule(nativeAppHidingActive: menuBarManager.nativeAppHidingExperiment.isActive),
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
