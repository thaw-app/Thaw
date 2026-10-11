//
//  LayoutDropCommit.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Carries out a drop made in the reorder editor through the same paths the
/// keyboard and the item menu use: record the order, then let the manager apply it.
@MainActor
enum LayoutDropCommit {
    struct Drop {
        let items: [MenuBarItem]
        let source: MenuBarSection.Name
        let target: MenuBarSection.Name
        let previousTargetOrder: [MenuBarItem]
        let targetOrder: [MenuBarItem]
    }

    /// Posts the reason and returns true when the drop cannot be carried out.
    static func refuses(_ drop: Drop, appState: AppState) -> Bool {
        guard let first = drop.items.first else { return true }
        if drop.target != .visible, drop.items.contains(where: \.tag.matchesVisibleControlItem) {
            appState.layoutFeedback.post(
                LayoutBarFeedbackCenter.Refusal(
                    title: String(
                        localized: "“\(Constants.displayName)” couldn’t move to \(MenuBarSection.Name.visible.displayString)",
                        comment: "Title shown when the Thaw control icon is dropped outside the Visible section"
                    ),
                    message: String(
                        localized: "The \(Constants.displayName) icon has to stay in Visible.",
                        comment: "Explanation shown when the Thaw control icon is dropped outside the Visible section"
                    )
                )
            )
            return true
        }
        let systemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        if drop.source == drop.target {
            let reorderable = systemItemHiding && LayoutBarPaddingView.allowsAnchoredSystemItemReordering(appState: appState)
            guard drop.target == .visible,
                  let fixed = drop.items.first(where: { !$0.isPhysicallyOrderable(experimentalSystemItemHiding: reorderable) })
            else {
                return false
            }
            appState.layoutFeedback.post(LayoutBarFeedbackCenter.itemNotMovable(itemName: fixed.displayName))
            return true
        }
        // A group is checked as a whole when it is assigned, so only a single item is gated here.
        guard drop.items.count == 1,
              !MenuBarBackendProvider.current.canAssign(first, to: drop.target, experimentalSystemItemHiding: systemItemHiding)
        else {
            return false
        }
        MenuBarSearchItemActions.postAssignmentRefusal(
            for: first,
            to: drop.target,
            experimentalSystemItemHiding: systemItemHiding,
            appState: appState
        )
        return true
    }

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
