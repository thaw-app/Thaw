//
//  ParkedItems.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Which live items macOS has parked off the menu bar, read from their frames.
nonisolated enum ParkedItems {
    /// The bar's vertical centre, read from a seated control item, and the windows of the
    /// items that sit off it: empty frames, frames below the bar band, and frames too far
    /// from that centre. Without a seated control only the first two can be told.
    static func parkedSetAndBarMidY(in items: [MenuBarItem]) -> (barMidY: CGFloat?, parkedIDs: Set<CGWindowID>) {
        let barMidY = items.first(where: {
            $0.tag.matchesVisibleControlItem && $0.bounds.midY <= MenuBarItemGeometry.maxOnBarMidY
        })?.bounds.midY
            ?? items.first(where: {
                $0.isControlItem && $0.bounds.width > 8 && $0.bounds.midY <= MenuBarItemGeometry.maxOnBarMidY
            })?.bounds.midY

        let parkedIDs = Set(items.compactMap { item -> CGWindowID? in
            guard item.bounds.width > 0, item.bounds.height > 0 else { return item.windowID }
            if item.bounds.midY > MenuBarItemGeometry.maxOnBarMidY {
                return item.windowID
            }
            guard let barMidY else { return nil }
            return abs(item.bounds.midY - barMidY) > MenuBarItemGeometry.maxDistanceFromBarMidY ? item.windowID : nil
        })

        return (barMidY, parkedIDs)
    }
}
