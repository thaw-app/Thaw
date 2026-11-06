//
//  MenuBarItem+Ordering.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

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

    /// Reorders the items macOS folds behind its overflow arrow into saved order.
    ///
    /// Folded items report frames stacked on the arrow, so their positions say
    /// nothing about the user's order. They keep the slots they occupy; only
    /// who sits in which slot changes. Items the saved order lacks keep their
    /// current order after the ones it knows.
    static func orderingOverflowStack(
        _ items: [MenuBarItem],
        overflowBounds: [CGRect],
        savedOrder: [String]
    ) -> [MenuBarItem] {
        let slots = items.indices.filter {
            MenuBarItemImageCache.isContaminatedByNativeOverflow(items[$0].bounds, overflowBounds: overflowBounds)
        }
        guard slots.count > 1 else { return items }
        let rank = { (item: MenuBarItem) in savedOrder.firstIndex(of: item.uniqueIdentifier) ?? .max }
        let stack = slots.map { items[$0] }.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
        var ordered = items
        for (slot, item) in zip(slots, stack) {
            ordered[slot] = item
        }
        return ordered
    }
}

nonisolated extension MenuBarItemCache {
    /// The cache with its Visible items folded behind the overflow arrow in
    /// saved order. A no-op without a display or an arrow on it.
    func orderingOverflowStack(savedOrder: [String: [String]]) -> Self {
        guard let displayID else { return self }
        var cache = self
        cache[.visible] = MenuBarItem.orderingOverflowStack(
            self[.visible],
            overflowBounds: MenuBarItemAXProvider.nativeOverflowControlBounds(on: displayID),
            savedOrder: savedOrder[MenuBarSectionName.visible.rawValue] ?? []
        )
        return cache
    }
}
