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
    /// Each screen's bar centre comes from its seated Visible control, or a wide control.
    /// Empty frames, frames on no bar, and frames too far from their own bar's centre
    /// are parked. A bar without a reference skips the distance check. The returned
    /// centre is the first screen's reference, falling back to the next with one.
    /// Without screen frames the original band measured from y zero is used.
    static func parkedSetAndBarMidY(in items: [MenuBarItem], screens: [CGRect]) -> (barMidY: CGFloat?, parkedIDs: Set<CGWindowID>) {
        func barIndex(holding frame: CGRect) -> Int? {
            guard !screens.isEmpty else {
                return frame.midY <= MenuBarItemGeometry.maxOnBarMidY ? 0 : nil
            }
            guard !frame.isEmpty else { return nil }
            if frame.origin.x == MenuBarItemGeometry.transientSentinelX {
                return screens.firstIndex { (0 ... MenuBarItemGeometry.maxOnBarMidY).contains(frame.midY - $0.minY) }
            }
            guard let screen = MenuBarItemGeometry.barScreen(holding: frame, among: screens) else { return nil }
            return screens.firstIndex(of: screen)
        }

        let barMidYs = (0 ..< max(1, screens.count)).map { index -> CGFloat? in
            let seated = items.filter { barIndex(holding: $0.bounds) == index }
            return seated.first(where: { $0.tag.matchesVisibleControlItem })?.bounds.midY
                ?? seated.first(where: { $0.isControlItem && $0.bounds.width > 8 })?.bounds.midY
        }

        let parkedIDs = Set(items.compactMap { item -> CGWindowID? in
            guard item.bounds.width > 0, item.bounds.height > 0, let index = barIndex(holding: item.bounds) else { return item.windowID }
            guard let barMidY = barMidYs[index] else { return nil }
            return abs(item.bounds.midY - barMidY) > MenuBarItemGeometry.maxDistanceFromBarMidY ? item.windowID : nil
        })

        return (barMidYs.compactMap(\.self).first, parkedIDs)
    }
}
