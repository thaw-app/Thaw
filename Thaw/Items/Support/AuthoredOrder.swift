//
//  AuthoredOrder.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// The order a section was authored in, read against a bar that only partly shows it.
///
/// A move is recorded by editing the authored order, a seat is found from the item authored
/// before it, and a walk the assertion left incomplete is filled in from the cache. All
/// three work from the items alone.
nonisolated enum AuthoredOrder {
    /// authored with item moved beside the target, so a respace realizes the
    /// move. Unchanged when the target is not in the record; a new arrival is
    /// inserted. Control items are never applied: laddering one can invert
    /// the dividers, and their seats are the structural pass's call.
    static func authoredOrder(
        _ authored: [String],
        applying destination: MoveDestination,
        to item: MenuBarItem
    ) -> [String] {
        guard !item.isControlItem, !destination.targetItem.isControlItem else { return authored }
        let itemID = item.uniqueIdentifier
        let targetID = destination.targetItem.uniqueIdentifier
        guard targetID != itemID, authored.contains(targetID) else { return authored }
        var order = authored.filter { $0 != itemID }
        guard let targetIndex = order.firstIndex(of: targetID) else { return authored }
        order.insert(itemID, at: destination.isRightward ? targetIndex + 1 : targetIndex)
        return order
    }

    /// The item immediately before item in an authored order, skipping the
    /// ones moving with it that are not yet seated, or nil when it is first.
    static func authoredPredecessor(
        of item: MenuBarItem,
        in order: [MenuBarItem]?,
        excluding movedIdentifiers: Set<String>
    ) -> MenuBarItem? {
        guard
            let order,
            let index = order.firstIndex(where: { $0.uniqueIdentifier == item.uniqueIdentifier })
        else { return nil }
        return order[..<index].last { !movedIdentifiers.contains($0.uniqueIdentifier) }
    }

    /// The live walk plus every cached managed item it does not carry, matched
    /// by tag regardless of window ID. Live geometry wins where both exist;
    /// a cached member only fills a gap the assertion has not re-allowed yet.
    static func completingPartialWalk(
        _ liveItems: [MenuBarItem],
        with cachedItems: [MenuBarItem]
    ) -> [MenuBarItem] {
        let missing = cachedItems.filter { cached in
            !liveItems.contains { $0.tag.matchesIgnoringWindowID(cached.tag) }
        }
        guard !missing.isEmpty else { return liveItems }
        // Insert at the last-known frame, not appended, or a concealed item's
        // slot lands in the visible lane. Never-rendered items go last.
        return (liveItems + missing).enumerated()
            .sorted { lhs, rhs in
                let lhsMissing = lhs.element.bounds.isEmpty && !liveItems.contains { $0.tag.matchesIgnoringWindowID(lhs.element.tag) }
                let rhsMissing = rhs.element.bounds.isEmpty && !liveItems.contains { $0.tag.matchesIgnoringWindowID(rhs.element.tag) }
                switch (lhsMissing, rhsMissing) {
                case (true, false): return false
                case (false, true): return true
                default:
                    if lhs.element.bounds.minX != rhs.element.bounds.minX {
                        return lhs.element.bounds.minX < rhs.element.bounds.minX
                    }
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}
