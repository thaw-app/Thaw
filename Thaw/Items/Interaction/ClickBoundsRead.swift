//
//  ClickBoundsRead.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

/// Where a click reads an item's frame right before it clicks.
///
/// The read of every running app goes through the Accessibility helper, which asks each one. A
/// click needs only its item's frame, so it reads the item's own app first and asks every app
/// only when that app didn't answer or no longer lists the item.
nonisolated enum ClickBoundsRead {
    /// The item's frame now: see bounds(for:ownApp:everyApp:).
    static func current(for item: MenuBarItem) async throws -> CGRect {
        try await bounds(
            for: item,
            ownApp: { _ in await ownApp(of: item) },
            everyApp: { await MenuBarItem.getMenuBarItems(option: .onScreen) }
        )
    }

    /// The fresh item to press for item: the one with its identity, or the app's only item when a
    /// transient title such as "Item-N" changed. Nil when the app has several and none matches,
    /// since a press there could open a sibling.
    static func pressTarget(for item: MenuBarItem, among fresh: [MenuBarItem]) -> MenuBarItem? {
        if let same = fresh.first(where: { $0.hasSameIdentity(as: item) }) {
            return same
        }
        let siblings = fresh.filter { $0.hasSameOwner(as: item) }
        return siblings.count == 1 ? siblings.first : nil
    }

    /// A fresh read of only the item's own processes, or nil when it has none or they didn't answer.
    static func ownApp(of item: MenuBarItem) async -> [MenuBarItem]? {
        let owners = item.reactionPIDs.filter { $0 > 0 }
        guard !owners.isEmpty else { return nil }
        return await MenuBarItemAXProvider.menuBarItemsForClickConcurrent(owners: owners)
    }

    /// The item's frame from its own app's read, or from every app's when that read is nil or
    /// lacks the item. An item with no known process goes straight to every app.
    static func bounds(
        for item: MenuBarItem,
        ownApp: (Set<pid_t>) async -> [MenuBarItem]?,
        everyApp: () async -> [MenuBarItem]
    ) async throws -> CGRect {
        let owners = item.reactionPIDs.filter { $0 > 0 }
        if !owners.isEmpty, let items = await ownApp(owners),
           let bounds = try? MenuBarItemManager.currentBounds(for: item, among: items)
        {
            return bounds
        }
        return try await MenuBarItemManager.currentBounds(for: item, among: everyApp())
    }
}
