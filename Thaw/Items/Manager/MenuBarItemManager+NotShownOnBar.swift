//
//  MenuBarItemManager+NotShownOnBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

// MARK: - Not Shown On Bar

extension MenuBarItemManager {
    /// Updates the streaks from the current inventory and publishes the
    /// items that have looked unshown long enough.
    func refreshItemsNotShownOnBar() {
        let visible = itemCache.managedItems(for: .visible)
        // Visible peers only: concealed items report parked frames on the
        // Thaw icon's seat. The Thaw icon itself is a visible item.
        let peers = visible
        var streaks = [MenuBarItemTag: Int]()
        for item in visible where NotShownOnBar.looksNotShown(item, among: peers) {
            streaks[item.tag] = (notShownStreaks[item.tag] ?? 0) + 1
        }
        notShownStreaks = streaks
        let tags = Set(streaks.filter { $0.value >= NotShownOnBar.notShownStreakThreshold }.keys)
        guard tags != itemsNotShownOnBarTags else { return }
        let added = tags.subtracting(itemsNotShownOnBarTags)
        if !added.isEmpty {
            MenuBarItemManager.diagLog.info(
                "Visible item(s) macOS is not drawing on the bar; offering them in the Thaw Bar: \(added.map(\.description).sorted())"
            )
        }
        itemsNotShownOnBarTags = tags
    }

    /// Visible items the bar is not showing, in their saved order.
    var itemsNotShownOnBar: [MenuBarItem] {
        guard !itemsNotShownOnBarTags.isEmpty else { return [] }
        return itemCache.managedItems(for: .visible).filter { itemsNotShownOnBarTags.contains($0.tag) }
    }
}
