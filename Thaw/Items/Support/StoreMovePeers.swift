//
//  StoreMovePeers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import MenuBarModel

/// The items a position write may treat as the moved item's neighbours.
///
/// With Native hiding macOS keeps a hidden app's icon laid out and only stops drawing it, so the
/// icon still reports a position on the bar, among the shown items. A position write finds
/// neighbours by position. Given such an icon it seats the moved item beside a neighbour nobody can
/// see, at a weight in among the hidden items, and macOS sends the item to the far end of the bar.
nonisolated enum StoreMovePeers {
    /// `live` without the items macOS is not drawing.
    ///
    /// `drawnOwners` is the processes with an item in MenuBarAgent's window, which is what is on
    /// the bar. An item whose process is not among them is left out. The section an item is
    /// assigned to does not say this: macOS cannot hide every app, and one it cannot hide stays on
    /// the bar, a real neighbour, while assigned to Hidden.
    ///
    /// When that window could not be read, the assigned section stands in: an item in a closed
    /// section is taken as not drawn, and everything is kept while a section is revealed.
    ///
    /// Everything is kept when the drop is beside an item that is not drawn, since that move is
    /// among the hidden items themselves. Thaw's own controls are always kept: they mark where the
    /// sections meet. The moved item and its target are always kept.
    static func drawn(
        among live: [MenuBarItem],
        moving item: MenuBarItem,
        target: MenuBarItem,
        drawnOwners: Set<pid_t>?,
        revealed: MenuBarSectionName?,
        section: (MenuBarItem) -> MenuBarSectionName
    ) -> [MenuBarItem] {
        guard drawnOwners != nil || revealed == nil else { return live }
        func isDrawn(_ peer: MenuBarItem) -> Bool {
            if let drawnOwners {
                return drawnOwners.contains(peer.sourcePID ?? peer.ownerPID)
            }
            return section(peer) == .visible
        }
        guard target.isControlItem || isDrawn(target) else { return live }
        return live.filter { peer in
            peer.isControlItem
                || peer.tag.matchesIgnoringWindowID(item.tag)
                || peer.tag.matchesIgnoringWindowID(target.tag)
                || isDrawn(peer)
        }
    }
}
