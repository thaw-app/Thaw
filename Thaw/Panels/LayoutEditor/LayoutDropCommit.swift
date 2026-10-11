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
}
