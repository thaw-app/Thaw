//
//  MenuBarItemManager+NotShownOnBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Visible items macOS does not actually draw on the bar.
///
/// MenuBarAgent can record an item's position and still lay it out under
/// another item or off the bar. Decided from geometry alone.
extension MenuBarItemManager {
    /// Consecutive cache passes an item has to look unshown before it counts.
    /// A reflow puts items briefly on top of each other; a stuck one stays.
    static let notShownStreakThreshold = 3

    /// Whether item, assigned to Visible, sits where nothing can see it:
    /// on a seat another item already occupies, or off the bar.
    static nonisolated func looksNotShown(_ item: MenuBarItem, among peers: [MenuBarItem]) -> Bool {
        guard !item.isControlItem, !item.isSystemClone else { return false }
        guard item.bounds.width > 0, item.bounds.height > 0 else { return true }
        if item.bounds.midY > MenuBarItemGeometry.maxOnBarMidY {
            return true
        }
        return item.hasPhantomFrame(among: peers)
    }

    /// Updates the streaks from the current inventory and publishes the
    /// items that have looked unshown long enough.
    func refreshItemsNotShownOnBar() {
        let visible = itemCache.managedItems(for: .visible)
        // Visible peers only: concealed items report parked frames on the
        // Thaw icon's seat. The Thaw icon itself is a visible item.
        let peers = visible
        var streaks = [MenuBarItemTag: Int]()
        for item in visible where Self.looksNotShown(item, among: peers) {
            streaks[item.tag] = (notShownStreaks[item.tag] ?? 0) + 1
        }
        notShownStreaks = streaks
        let tags = Set(streaks.filter { $0.value >= Self.notShownStreakThreshold }.keys)
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
