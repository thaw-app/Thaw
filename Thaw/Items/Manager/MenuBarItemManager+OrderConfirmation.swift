//
//  MenuBarItemManager+OrderConfirmation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

extension MenuBarItemManager {
    /// liveOrderMatches, from a read that has every item of desiredOrder the item cache lists in section.
    /// The planner finds no move for an item the read missed, so a short read would confirm an order the bar lacks.
    @MainActor
    func liveOrderConfirmed(
        _ desiredOrder: [String],
        section: MenuBarSection.Name,
        controller: any MenuBarSectionControlling,
        items: [MenuBarItem]
    ) -> Bool {
        let missed = Self.desiredItemsMissing(from: items, desiredOrder: desiredOrder, cached: itemCache[section])
        guard missed.isEmpty else {
            Self.diagLog.info("Not confirming the \(section.logString) order: the read missed \(missed.sorted())")
            return false
        }
        return liveOrderMatches(desiredOrder, section: section, controller: controller, items: items)
    }

    /// The items of desiredOrder that the cache has and the read doesn't. One the cache lacks too, such as
    /// a closed app's, isn't expected in the read.
    static nonisolated func desiredItemsMissing(from items: [MenuBarItem], desiredOrder: [String], cached: [MenuBarItem]) -> Set<String> {
        Set(desiredOrder)
            .intersection(cached.map(\.uniqueIdentifier))
            .subtracting(items.map(\.uniqueIdentifier))
    }
}
