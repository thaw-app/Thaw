//
//  MenuBarSearchRecents.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Recently activated items in the menu bar search panel, shown when the
/// query is empty.
///
/// Recents are the search panel's entire memory model: no usage counters,
/// no learning, just the last few items the user activated, most recent first.
///
/// Items are persisted as canonical persistent identifiers, the same
/// canonicalization the persisted section order and item groups go through,
/// so an identifier survives title churn (iStat Menus and friends). An
/// identifier that resolves to no live item is skipped at read time and never
/// written back: stale entries expire silently on their own, and a failed
/// activation attempt must not cost the user anything.
@MainActor
final class MenuBarSearchRecents {
    /// Most-recent-first. Hard cap keeps the empty-query list from turning
    /// into a second full inventory.
    private static let limit = 8

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored identifiers, most recent first.
    var identifiers: [String] {
        defaults.stringArray(forKey: Defaults.Key.menuBarSearchRecents.rawValue) ?? []
    }

    /// Moves item to the front, deduplicating and capping.
    func record(_ item: MenuBarItem) {
        guard let identifier = MenuBarItemTag.canonicalPersistentIdentifiers([item.tag.tagIdentifier]).first else {
            return
        }
        var updated = identifiers.filter { $0 != identifier }
        updated.insert(identifier, at: 0)
        if updated.count > Self.limit {
            updated.removeLast(updated.count - Self.limit)
        }
        defaults.set(updated, forKey: Defaults.Key.menuBarSearchRecents.rawValue)
    }

    /// Resolves stored identifiers to live items, preserving recency order.
    ///
    /// Resolution scans every managed section rather than remembering where
    /// the item lived: an item that migrated sections between activations is
    /// still the same identity. Unresolvable entries are dropped from the
    /// result only, see the class comment for why they stay in storage.
    func resolve(in manager: MenuBarItemManager) -> [MenuBarItem] {
        let storedIdentifiers = identifiers
        guard !storedIdentifiers.isEmpty else { return [] }
        let wanted = Set(storedIdentifiers)
        var itemsBySection = [MenuBarItem]()
        var seen = Set<String>()
        // Iteration order is irrelevant to the result, recency order is
        // preserved from storage; this loop only resolves identifiers.
        for name in MenuBarSection.Name.allCases {
            for item in manager.managedItems(for: name) where !item.isControlItem {
                guard let identifier = MenuBarItemTag.canonicalPersistentIdentifiers([item.tag.tagIdentifier]).first,
                      wanted.contains(identifier)
                else { continue }
                // A canonical identifier can legitimately resolve more than
                // once across sections while an item is mid-move; first hit
                // wins and duplicates are suppressed.
                guard seen.insert(identifier).inserted else { continue }
                itemsBySection.append(item)
            }
        }
        return itemsBySection.sorted { a, b in
            let indexA = storedIdentifiers.firstIndex(of: MenuBarItemTag.canonicalPersistentIdentifiers([a.tag.tagIdentifier]).first ?? "") ?? .max
            let indexB = storedIdentifiers.firstIndex(of: MenuBarItemTag.canonicalPersistentIdentifiers([b.tag.tagIdentifier]).first ?? "") ?? .max
            return indexA < indexB
        }
    }
}
