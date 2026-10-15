//
//  ItemConcealment.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Whether an item is hidden right now, by any concealment set the section controller publishes.
/// Both sets hold canonical keys, so a raw identifier is canonicalized first or an item with a ticking title is never found.
nonisolated enum ItemConcealment {
    static func isConcealed(_ uniqueIdentifier: String, in concealed: Set<String>) -> Bool {
        concealed.contains(MenuBarItemTag.canonicalPersistentIdentifier(uniqueIdentifier))
    }
}

extension MenuBarSectionControlling {
    /// Covers a Visible item that automatic overflow conceals, too.
    func isEffectivelyConcealed(_ item: MenuBarItem) -> Bool {
        ItemConcealment.isConcealed(item.uniqueIdentifier, in: effectivelyConcealedIdentifiers)
    }
}
