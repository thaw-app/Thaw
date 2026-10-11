//
//  LayoutDropCommit+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

extension LayoutDropCommit {
    static func commit(_ drop: Drop, appState: AppState, undoManager: UndoManager?, finished: @escaping @MainActor () -> Void) {
        guard drop.source != drop.target else {
            LayoutBarKeyboard.applySectionOrder(
                drop.targetOrder,
                previousOrder: drop.previousTargetOrder,
                section: drop.target,
                appState: appState,
                undoManager: undoManager,
                actionName: String(localized: "Move \(drop.items.first?.displayName ?? "")")
            )
            finished()
            return
        }
        let controller = appState.menuBarManager.sectionController
        ExplicitLayoutEdit.task {
            // Seated before the assertion flips, as for a move from the item menu.
            await appState.itemManager.seatItemsForSectionTransition(
                drop.items,
                to: drop.target,
                orderedAs: drop.targetOrder
            ) {
                guard drop.items.count == 1, let item = drop.items.first else {
                    assignGroup(drop, appState: appState)
                    return
                }
                controller.setSection(drop.target, item: item)
                controller.setSectionOrder(from: drop.targetOrder, for: drop.target)
                appState.itemManager.scheduleSectionOrderApply(for: drop.target)
            }
            await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
            finished()
        }
    }

    /// A group lands in the target's stored order, as it does from the item menu.
    private static func assignGroup(_ drop: Drop, appState: AppState) {
        guard let refusal = appState.menuBarManager.setSection(drop.target, items: drop.items, atomically: true) else {
            return
        }
        let sourceItems = appState.itemManager.managedItems(for: drop.source)
        appState.layoutFeedback.post(
            LayoutBarFeedbackCenter.blockedGroupMove(
                groupName: MenuBarSearchItemActions.groupDisplayName(for: drop.items, in: sourceItems, appState: appState),
                section: drop.target,
                refusal: refusal
            )
        )
    }
}
