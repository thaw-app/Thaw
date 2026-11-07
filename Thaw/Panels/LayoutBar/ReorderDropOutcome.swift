//
//  ReorderDropOutcome.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Whether a single-item drop landed where it was dropped, and what Layout says when it didn't.
enum ReorderDropOutcome {
    /// True when the item sits beside its target on the drop's side, false when it sits elsewhere,
    /// and nil when the read can't tell, so a move that may have worked raises no alarm.
    static nonisolated func landed(
        _ item: MenuBarItem,
        at destination: MenuBarItemManager.MoveDestination,
        in liveItems: [MenuBarItem]
    ) -> Bool? {
        let ordered = liveItems.filter { $0.bounds.width > 0 }.sorted { $0.bounds.minX < $1.bounds.minX }
        guard let itemIndex = ordered.firstIndex(where: { $0.tag.matchesIgnoringWindowID(item.tag) }),
              let targetIndex = ordered.firstIndex(where: { $0.tag.matchesIgnoringWindowID(destination.targetItem.tag) })
        else { return nil }
        return itemIndex == targetIndex + (destination.isRightward ? 1 : -1)
    }

    static nonisolated func missedDrop(itemName: String) -> LayoutBarFeedbackCenter.Refusal {
        LayoutBarFeedbackCenter.Refusal(
            title: String(
                localized: "Couldn’t move “\(itemName)”",
                comment: "Title shown when a dragged menu bar item didn't end up where it was dropped"
            ),
            message: String(
                localized: "macOS put it back.",
                comment: "Explanation shown when a dragged menu bar item didn't end up where it was dropped"
            )
        )
    }

    /// Logs the failed move and, once a fresh read shows the item elsewhere, tells the user.
    @MainActor
    static func reportFailure(
        of item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        appState: AppState,
        log: DiagLog,
        readLiveItems: (Set<pid_t>) async -> [MenuBarItem]? = { await MenuBarItem.getFreshMenuBarItemsForMove(priorityPIDs: $0) }
    ) async {
        log.error("Reorder move failed for \(item.logString); visible order was not persisted")
        let owners = Set([item.ownerPID, item.sourcePID, destination.targetItem.ownerPID, destination.targetItem.sourcePID].compactMap(\.self))
        guard let liveItems = await readLiveItems(owners), landed(item, at: destination, in: liveItems) == false else { return }
        appState.layoutFeedback.post(missedDrop(itemName: MenuBarItemDisplayName.displayName(for: item)))
    }
}
