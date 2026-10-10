//
//  MenuBarItem+Ordering.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Exposes non-optional section buckets so CacheRebucketter can use app caches without an app-target dependency.
public protocol MenuBarSectionBucketed {
    subscript(_: MenuBarSectionName) -> [MenuBarItem] { get set }
}

public extension MenuBarItem {
    static func sortByLeadingEdge(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { $0.bounds.minX < $1.bounds.minX }
    }

    static func sortByVisualCenter(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { $0.bounds.midX < $1.bounds.midX }
    }

    /// Break midX ties by identifier to keep cache signatures stable during transient reflows.
    static func sortByVisualCenterThenIdentifier(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { lhs, rhs in
            if lhs.bounds.midX == rhs.bounds.midX {
                return lhs.uniqueIdentifier < rhs.uniqueIdentifier
            }
            return lhs.bounds.midX < rhs.bounds.midX
        }
    }
}
