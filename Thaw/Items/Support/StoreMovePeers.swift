//
//  StoreMovePeers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// The items a position write may treat as the moved item's neighbours.
///
/// With Native hiding macOS keeps a hidden app's icon laid out and only stops drawing it, so the
/// icon still reports a position on the bar, among the shown items. A position write finds
/// neighbours by position. Given such an icon it seats the moved item beside a neighbour nobody can
/// see, at a weight in among the hidden items, and macOS sends the item to the far end of the bar.
nonisolated enum StoreMovePeers {
    /// `live` without the items that are in a closed section, which are not drawn.
    ///
    /// Everything is kept while a section is revealed, and when the move starts or ends in a closed
    /// section, since those moves are among the hidden items themselves. Thaw's own controls are
    /// always kept: they mark where the sections meet.
    static func drawn(
        among live: [MenuBarItem],
        moving item: MenuBarItem,
        target: MenuBarItem,
        revealed: MenuBarSectionName?,
        section: (MenuBarItem) -> MenuBarSectionName
    ) -> [MenuBarItem] {
        guard revealed == nil else { return live }
        guard target.isControlItem || section(target) == .visible else { return live }
        return live.filter { peer in
            peer.isControlItem
                || peer.tag.matchesIgnoringWindowID(item.tag)
                || peer.tag.matchesIgnoringWindowID(target.tag)
                || section(peer) == .visible
        }
    }
}
