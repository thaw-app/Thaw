//
//  NotShownOnBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Visible items macOS does not actually draw on the bar.
///
/// MenuBarAgent can record an item's position and still lay it out under
/// another item or off the bar. Decided from geometry alone.
nonisolated enum NotShownOnBar {
    /// Consecutive cache passes an item has to look unshown before it counts.
    /// A reflow puts items briefly on top of each other; a stuck one stays.
    static let notShownStreakThreshold = 3

    /// Whether item, assigned to Visible, sits where nothing can see it:
    /// on a seat another item already occupies, or off the bar.
    static func looksNotShown(_ item: MenuBarItem, among peers: [MenuBarItem]) -> Bool {
        guard !item.isControlItem, !item.isSystemClone else { return false }
        guard item.bounds.width > 0, item.bounds.height > 0 else { return true }
        if item.bounds.midY > MenuBarItemGeometry.maxOnBarMidY {
            return true
        }
        return item.hasPhantomFrame(among: peers)
    }
}
