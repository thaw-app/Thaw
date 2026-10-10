//
//  RevealTurns.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// The two passes a reveal asks for, each run as one turn through the repair orchestrator.
/// The kit cancels its task on hide, so a restore still queued then never writes.
@MainActor
enum RevealTurns {
    /// Puts the revealed section back in its saved order.
    static func restoreOrder(revealing section: MenuBarSectionName, on itemManager: MenuBarItemManager) async {
        let read: () async -> [MenuBarItem]? = {
            // Nothing is restored while the user arranges, so nothing is read.
            guard !itemManager.arrangementIsManual, !itemManager.isUserArrangingMenuBar else { return nil }
            return await MenuBarItem.getMenuBarItems(option: .activeSpace)
        }
        itemManager.repairs.request(.revealReconcile, cause: .sectionRevealed)
        let aftermath = RepairTurn.Aftermath()
        await RepairTurn.run(.revealReconcile, priority: .user, on: itemManager.repairs, read: read) { items, permit in
            await itemManager.synchronizeRevealedOrder(revealing: section, readBeforeTurn: items, aftermath: aftermath, permit: permit)
        }
        await aftermath.readCacheIfOwed { await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
    }

    /// Moves items that ended on the wrong side of a divider after a recovery.
    static func reconcileBoundaries(revealing section: MenuBarSectionName, on itemManager: MenuBarItemManager) async {
        let nothingToRead: () async -> Bool? = { nil }
        itemManager.repairs.request(.revealReconcile, cause: .sectionRevealed)
        let aftermath = RepairTurn.Aftermath()
        await RepairTurn.run(.revealReconcile, priority: .user, on: itemManager.repairs, read: nothingToRead) { _, permit in
            await itemManager.reconcileSectionBoundaries(revealing: section, aftermath: aftermath, permit: permit)
        }
        await aftermath.readCacheIfOwed { await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true) }
    }
}
