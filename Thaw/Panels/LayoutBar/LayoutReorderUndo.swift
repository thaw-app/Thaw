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
    /// The order before a same-section drag: the dragged item back in the slot it left.
    static nonisolated func orderBeforeDrag(of item: MenuBarItem, in order: [MenuBarItem], from index: Int?) -> [MenuBarItem]? {
        guard let index, let current = order.firstIndex(where: { $0.tag == item.tag }) else { return nil }
        var previous = order
        previous.remove(at: current)
        previous.insert(item, at: min(max(index, 0), previous.count))
        return previous.map(\.uniqueIdentifier) == order.map(\.uniqueIdentifier) ? nil : previous
    }

    /// Registers an undo that restores previous, once the reorder took effect.
    static func register(
        _ order: [MenuBarItem]?,
        previous: [MenuBarItem]?,
        of item: MenuBarItem,
        section: MenuBarSection.Name,
        appState: AppState
    ) {
        guard let order, let previous else { return }
        let undoManager = appState.layoutUndo
        let actionName = String(localized: "Move \(item.displayName)")
        undoManager.registerUndo(withTarget: appState) { [weak undoManager] appState in
            LayoutBarKeyboard.applySectionOrder(
                previous,
                previousOrder: order,
                section: section,
                appState: appState,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager.setActionName(actionName)
    }
}
