//
//  MenuBarItemManager+AlphabeticalOrder.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

enum MenuBarItemSortDirection {
    case ascending
    case descending
}

@MainActor
enum MenuBarItemAlphabeticalOrder {
    static func sorted(
        _ items: [MenuBarItem],
        groups: [ResolvedGroup],
        direction: MenuBarItemSortDirection
    ) -> [MenuBarItem] {
        var fixed = Set(items.indices.filter {
            items[$0].isControlItem || items[$0].tag.isLayoutAnchoredSystemItem
                || items[$0].isNativeOverflowControl || items[$0].tag.isCaptureActivityIndicator
                || MenuBarSpacerManager.isSpacerTag(items[$0].tag)
        })
        // A group crossing a fixed anchor cannot move as a block without moving that anchor.
        for group in groups where group.range.contains(where: fixed.contains) {
            fixed.formUnion(group.memberIndices)
        }
        var result = items
        var start = 0
        for end in Array(fixed).sorted() + [items.count] {
            let range = start ..< end
            var claimed = Set<Int>()
            var units = [(name: String, indices: [Int])]()
            for index in range where !claimed.contains(index) {
                let group = groups.first {
                    $0.memberIndices.contains(index) && $0.memberIndices.allSatisfy(range.contains)
                }
                let indices = group?.memberIndices ?? [index]
                claimed.formUnion(indices)
                units.append((group?.displayName ?? items[index].displayName, indices))
            }
            units.sort {
                let comparison = $0.name.localizedStandardCompare($1.name)
                if comparison == .orderedSame {
                    return $0.indices[0] < $1.indices[0]
                }
                return comparison == (direction == .ascending ? .orderedAscending : .orderedDescending)
            }
            let reordered = units.flatMap(\.indices).map { items[$0] }
            result.replaceSubrange(range, with: reordered)
            start = end + 1
        }
        return result
    }
}

extension MenuBarItemManager {
    func sortItems(in section: MenuBarSection.Name, direction: MenuBarItemSortDirection) {
        guard let appState else { return }
        let controller = appState.menuBarManager.sectionController
        let items = MenuBarBackendProvider.current.rebucket(
            itemCache,
            hider: controller,
            allowsAlwaysHidden: appState.settings.advanced.enableAlwaysHiddenSection
        ).managedItems(for: section)
        let sorted = MenuBarItemAlphabeticalOrder.sorted(
            items,
            groups: appState.itemGroupManager.resolvedGroups(for: items),
            direction: direction
        )
        guard sorted.map(\.uniqueIdentifier) != items.map(\.uniqueIdentifier) else { return }
        controller.setSectionOrder(from: sorted, for: section)
        Self.diagLog.info("Alphabetical sort: section=\(section.rawValue) direction=\(String(describing: direction)) items=\(sorted.count)")
        // The sort menu is the user arranging in Layout, so Manual lets it move the items.
        ExplicitLayoutEdit.perform {
            scheduleSectionOrderApply(for: section)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if section != .visible, let revealed = controller.revealedSection,
                   revealed == section || (section == .hidden && revealed == .alwaysHidden)
                {
                    await applySectionItemOrder(
                        sections: [section],
                        controller: controller,
                        whileRevealing: revealed,
                        reason: .userReorder
                    )
                }
                await cacheItemsRegardless(skipRecentMoveCheck: true)
            }
        }
    }
}
