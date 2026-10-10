//
//  MenuBarItem+Ordering.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

nonisolated extension MenuBarItem {
    /// Leading-edge order with a stable identifier tie-break.
    ///
    /// Items can tie on `minX` during a reflow, and Swift's sort isn't
    /// stable, so ties would read as spontaneous swaps. `uniqueIdentifier` is
    /// stable across launches.
    static func sortByLeadingEdgeThenIdentifier(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { lhs, rhs in
            if lhs.bounds.minX == rhs.bounds.minX {
                return lhs.uniqueIdentifier < rhs.uniqueIdentifier
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }
    }
}
