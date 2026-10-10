//
//  MenuBarItemManager+OrderRecording.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

extension MenuBarItemManager {
    /// Use observed order, not stale pane order; AX-missing members retain proposed slots.
    /// A vanished mover cannot commit; the controller still filters and preserves overflow.
    static nonisolated func sectionOrderAfterCompletedMove(
        of item: MenuBarItem,
        proposedOrder: [MenuBarItem],
        liveItems: [MenuBarItem]
    ) -> [MenuBarItem]? {
        let proposedIDs = Set(proposedOrder.map(\.uniqueIdentifier))
        var observedIDs = Set<String>()
        let observed = MenuBarItem.sortByLeadingEdge(liveItems).filter {
            proposedIDs.contains($0.uniqueIdentifier) &&
                $0.isOnScreen && !$0.bounds.isEmpty && !$0.isSystemClone &&
                observedIDs.insert($0.uniqueIdentifier).inserted
        }
        guard observedIDs.contains(item.uniqueIdentifier) else { return nil }
        var iterator = observed.makeIterator()
        return proposedOrder.map { member in
            guard observedIDs.contains(member.uniqueIdentifier) else { return member }
            return iterator.next() ?? member
        }
    }

    /// The Visible order to keep when an arrival disturbed the items already on the bar, or nil to mirror as is.
    /// A ⌘-drag leaves the item set unchanged, so only a pure arrival counts; the newcomer keeps its slot.
    static nonisolated func visibleOrderPreservedAcrossArrival(
        savedOrder: [String],
        mirroredOrder: [String],
        previousLive: Set<String>,
        currentLive: Set<String>
    ) -> [String]? {
        guard currentLive != previousLive, currentLive.isSuperset(of: previousLive) else { return nil }
        let savedStayed = savedOrder.filter(previousLive.contains)
        let mirroredStayed = mirroredOrder.filter(previousLive.contains)
        guard savedStayed != mirroredStayed,
              savedStayed.count == mirroredStayed.count,
              Set(savedStayed) == Set(mirroredStayed)
        else { return nil }
        var iterator = savedStayed.makeIterator()
        return mirroredOrder.map { identifier in
            previousLive.contains(identifier) ? (iterator.next() ?? identifier) : identifier
        }
    }

    /// User drops already verified their position; only structural edits and repairs need another rewrite.
    static nonisolated func shouldNormalizeStructureAfterMove(
        item: MenuBarItem,
        destination: MoveDestination,
        isUserInitiated: Bool
    ) -> Bool {
        !isUserInitiated || item.isControlItem || destination.targetItem.isControlItem
    }
}
