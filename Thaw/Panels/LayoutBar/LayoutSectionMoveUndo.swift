//
//  LayoutSectionMoveUndo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Undo for dragging an item into another section, matching the keyboard move, which could already be undone.
@MainActor
enum LayoutSectionMoveUndo {
    /// Assigns item to target and, when that changes its section, registers an undo that moves it back.
    static func setSection(
        _ target: MenuBarSection.Name,
        of item: MenuBarItem,
        from source: MenuBarSection.Name,
        controller: (any MenuBarSectionControlling)?,
        appState: AppState?,
        undoManager: UndoManager?
    ) {
        controller?.setSection(target, item: item)
        registerUndo(of: item, from: source, to: target, appState: appState, undoManager: undoManager)
    }

    static func registerUndo(
        of item: MenuBarItem,
        from source: MenuBarSection.Name,
        to target: MenuBarSection.Name,
        appState: AppState?,
        undoManager: UndoManager?
    ) {
        guard source != target, let appState, let undoManager else { return }
        let tag = item.tag
        let actionName = String(localized: "Move \(item.displayName)")
        // The undo manager doesn't keep its target alive, so the target is the long-lived app state.
        undoManager.registerUndo(withTarget: appState) { [weak undoManager] appState in
            LayoutBarKeyboard.performSectionMove(
                tag: tag,
                from: target,
                to: source,
                appState: appState,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager.setActionName(actionName)
    }
}
