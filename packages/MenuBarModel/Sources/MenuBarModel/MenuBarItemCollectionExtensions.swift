//
//  MenuBarItemCollectionExtensions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// MARK: - Collection where Element == MenuBarItem

public extension Collection<MenuBarItem> {
    func firstIndex(matching tag: MenuBarItemTag) -> Index? {
        if tag.matchesVisibleControlItem {
            return firstIndex { $0.tag.matchesVisibleControlItem }
        }
        return firstIndex { $0.tag == tag }
    }
}

// MARK: - RangeReplaceableCollection where Element == MenuBarItem

public extension RangeReplaceableCollection<MenuBarItem> {
    /// Removes and returns the first match, or nil if no item matches.
    mutating func removeFirst(matching tag: MenuBarItemTag) -> MenuBarItem? {
        guard let index = firstIndex(matching: tag) else {
            return nil
        }
        return remove(at: index)
    }
}

// MARK: - Sequence where Element == MenuBarItem

public extension Sequence<MenuBarItem> {
    func first(matching tag: MenuBarItemTag) -> MenuBarItem? {
        if tag.matchesVisibleControlItem {
            return first { $0.tag.matchesVisibleControlItem }
        }
        return first { $0.tag == tag }
    }
}

// MARK: - Comparable

public extension Comparable {
    /// Requires min to be no greater than max.
    func clamped(min: Self, max: Self) -> Self {
        precondition(min <= max, "Clamp requires min <= max")
        return Swift.min(Swift.max(self, min), max)
    }

    func clamped(to range: ClosedRange<Self>) -> Self {
        clamped(min: range.lowerBound, max: range.upperBound)
    }
}
