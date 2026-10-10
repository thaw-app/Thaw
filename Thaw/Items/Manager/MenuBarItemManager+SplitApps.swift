//
//  MenuBarItemManager+SplitApps.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Apps whose items are assigned to more than one section.
///
/// macOS 27 hides an app as a whole, so while any of its items is concealed
/// the rest are too, whatever Layout shows. A split comes from paths the
/// automatic groups do not see: a later item arriving into the new-items
/// section, an ungrouped app moved piecemeal, a layout carried over from
/// macOS 26.
extension MenuBarItemManager {
    /// The concealed section an item's app pulls it into, or nil when the
    /// item is shown or its app is not split.
    func sectionHidingItemWithItsApp(_ item: MenuBarItem, appState: AppState) -> MenuBarSection.Name? {
        let controller = appState.menuBarManager.sectionController
        guard controller.authoredSection(for: item.uniqueIdentifier) == .visible else { return nil }
        return Self.concealingSiblingSection(
            of: item,
            among: itemCache.managedItems,
            section: { controller.authoredSection(for: $0.uniqueIdentifier) }
        )
    }

    /// The concealed section another item of item's app is in, preferring
    /// Always Hidden. Only apps that can be hidden count; system hosts carry
    /// many unrelated modules under one owner.
    static nonisolated func concealingSiblingSection(
        of item: MenuBarItem,
        among items: [MenuBarItem],
        section: (MenuBarItem) -> MenuBarSection.Name
    ) -> MenuBarSection.Name? {
        guard MenuBarItemGrouping.isGroupable(item.tag) else { return nil }
        let siblings = items.filter {
            $0.tag.namespace == item.tag.namespace
                && $0.uniqueIdentifier != item.uniqueIdentifier
                && MenuBarItemGrouping.isGroupable($0.tag)
        }
        let sections = Set(siblings.map(section))
        if sections.contains(.alwaysHidden) {
            return .alwaysHidden
        }
        if sections.contains(.hidden) {
            return .hidden
        }
        return nil
    }

    /// The section a newly arrived item's app already lives in, when all its
    /// other items agree on one.
    static nonisolated func sectionOfAppSiblings(
        of item: MenuBarItem,
        among items: [MenuBarItem],
        section: (MenuBarItem) -> MenuBarSection.Name
    ) -> MenuBarSection.Name? {
        guard MenuBarItemGrouping.isGroupable(item.tag) else { return nil }
        let sections = Set(
            items
                .filter {
                    $0.tag.namespace == item.tag.namespace
                        && $0.uniqueIdentifier != item.uniqueIdentifier
                        && MenuBarItemGrouping.isGroupable($0.tag)
                }
                .map(section)
        )
        return sections.count == 1 ? sections.first : nil
    }

    /// Every item of item's app, so the app can be moved as one.
    func appItems(for item: MenuBarItem) -> [MenuBarItem] {
        itemCache.managedItems.filter {
            $0.tag.namespace == item.tag.namespace && MenuBarItemGrouping.isGroupable($0.tag)
        }
    }
}
