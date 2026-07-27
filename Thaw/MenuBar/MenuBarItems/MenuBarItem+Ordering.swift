//
//  MenuBarItem+Ordering.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

nonisolated extension MenuBarItem {
    /// Leading-edge order with a stable identifier tie-break.
    ///
    /// Two items can report the same `minX` during a transient reflow — while
    /// the bar is mid-move, while an owner is re-laying out its own item, or
    /// while a zero-width control item sits exactly on a neighbor's edge.
    /// `Array.sort(by:)` is not a stable sort in Swift, so a bare
    /// `minX < minX` comparison is free to return those tied items in a
    /// different relative order on every pass. Anywhere the result becomes an
    /// *order of record* — a persisted layout, a cache signature, a
    /// before/after comparison that decides whether to act — that instability
    /// reads as a spontaneous swap.
    ///
    /// `uniqueIdentifier` is the tie-break because it is already the
    /// codebase's launch-stable identity (`namespace:title[:index]`), so the
    /// resolved order is reproducible across passes *and* across relaunches.
    static func sortByLeadingEdgeThenIdentifier(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { lhs, rhs in
            if lhs.bounds.minX == rhs.bounds.minX {
                return lhs.uniqueIdentifier < rhs.uniqueIdentifier
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }
    }
}
