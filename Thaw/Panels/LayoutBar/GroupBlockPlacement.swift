//
//  GroupBlockPlacement.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Where a dragged group must sit beside its anchor, and when to stop trying to put it there.
nonisolated struct GroupBlockPlacement {
    /// The members left to right, the order the block must end in.
    let members: [MenuBarItemTag]

    /// The neighbour outside the group that borders the block's destination.
    let anchor: MenuBarItemTag

    let insertsLeftOfAnchor: Bool

    static let maxPasses = 4

    /// The block's first index in live, as the anchor implies it and clamped to the section.
    /// The drop described a section that may have changed shape since, so the raw slot can fall off either edge.
    func slot(in live: [MenuBarItemTag]) -> (raw: Int, clamped: Int)? {
        guard let anchorIndex = live.firstIndex(of: anchor) else { return nil }
        let raw = insertsLeftOfAnchor ? anchorIndex - members.count : anchorIndex + 1
        return (raw, min(max(raw, 0), max(live.count - members.count, 0)))
    }

    /// Whether the members sit contiguously, in order, in their slot.
    func isPlaced(in live: [MenuBarItemTag]) -> Bool {
        guard let start = slot(in: live)?.clamped else { return false }
        return members.indices.allSatisfy {
            live.indices.contains(start + $0) && live[start + $0] == members[$0]
        }
    }

    /// A pass that moved no member cannot do better on a repeat: each move
    /// already waited for macOS to act, and repeating only keeps Layout dimmed.
    static func shouldRunAnotherPass(after pass: Int, membersMoved: Int) -> Bool {
        pass < maxPasses && membersMoved > 0
    }
}
