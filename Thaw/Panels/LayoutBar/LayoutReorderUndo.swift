//
//  LayoutReorderUndo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Undo for dragging an item within its section. Undo goes through the keyboard's
/// order commit, so it applies the way a move does and registers its own redo.
@MainActor
enum LayoutReorderUndo {
    /// The order before a same-section drag: the items captured when the drag began.
    /// Nil when the drag began unrecorded or reordered nothing.
    static nonisolated func orderBeforeDrag(_ dragStart: [MenuBarItem]?, matching current: [MenuBarItem]) -> [MenuBarItem]? {
        guard let dragStart else { return nil }
        return dragStart.map(\.uniqueIdentifier) == current.map(\.uniqueIdentifier) ? nil : dragStart
    }

    /// Registers an undo that restores previous, once the reorder took effect.
    /// actionName names a group reorder; it defaults to the item's name.
    static func register(
        _ order: [MenuBarItem]?,
        previous: [MenuBarItem]?,
        of item: MenuBarItem,
        section: MenuBarSection.Name,
        appState: AppState,
        actionName: String? = nil
    ) {
        guard let order, let previous else { return }
        let undoManager = appState.layoutUndo
        let name = actionName ?? String(localized: "Move \(item.displayName)")
        undoManager.registerUndo(withTarget: appState) { [weak undoManager] appState in
            LayoutBarKeyboard.applySectionOrder(
                previous,
                previousOrder: order,
                section: section,
                appState: appState,
                undoManager: undoManager,
                actionName: name
            )
        }
        undoManager.setActionName(name)
    }

    /// Registers a reordered group's undo once the new order is committed. A group
    /// moves as one block, so its undo restores the whole order the drag began with.
    static func registerGroupReorder(
        _ reordered: [MenuBarItem],
        dragStart: [MenuBarItem]?,
        section: MenuBarSection.Name,
        appState: AppState
    ) {
        guard let first = reordered.first else { return }
        register(
            reordered,
            previous: orderBeforeDrag(dragStart, matching: reordered),
            of: first,
            section: section,
            appState: appState,
            actionName: String(localized: "Move Group")
        )
    }

    /// The section's persistence order, with anchored system items trailed where the section calls for it.
    /// A drop commits this order and a drag's undo restores it.
    static func sectionOrder(for container: LayoutBarContainer) -> [MenuBarItem] {
        let orderedItems = LayoutBarPaddingView.layoutItemsForPersistence(from: container.arrangedViews)
        guard container.section != .visible,
              !LayoutBarPaddingView.allowsAnchoredSystemItemReordering(appState: container.appState)
        else {
            return orderedItems
        }
        return MenuBarBackendProvider.current.anchoredSystemItemsTrail(in: orderedItems)
    }
}
