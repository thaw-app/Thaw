//
//  MenuBarItem+Ordering.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

nonisolated extension MenuBarItem {
    static func sortByLeadingEdge(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { $0.bounds.minX < $1.bounds.minX }
    }

    static func sortByVisualCenter(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { $0.bounds.midX < $1.bounds.midX }
    }

    /// Visual-center order with a stable identifier tie-break for cache signatures
    /// where two items can share the same midX during transient reflows.
    static func sortByVisualCenterThenIdentifier(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { lhs, rhs in
            if lhs.bounds.midX == rhs.bounds.midX {
                return lhs.uniqueIdentifier < rhs.uniqueIdentifier
            }
            return lhs.bounds.midX < rhs.bounds.midX
        }
    }
}
