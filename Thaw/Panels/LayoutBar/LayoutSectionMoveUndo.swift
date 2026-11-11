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

    /// Moves a group as a whole and, when that worked, registers an undo that moves it back.
    /// Returns the refusal, so a group that can't move leaves no undo step.
    static func assignGroup(
        _ members: [MenuBarItem],
        to target: MenuBarSection.Name,
        from source: MenuBarSection.Name,
        appState: AppState?
    ) -> MenuBarGroupMoveRefusal? {
        guard let appState else { return nil }
        let refusal = appState.menuBarManager.setSection(target, items: members, atomically: true)
        if refusal == nil {
            registerGroupUndo(of: members, from: source, to: target, appState: appState)
        }
        return refusal
    }

    static func registerGroupUndo(
        of members: [MenuBarItem],
        from source: MenuBarSection.Name,
        to target: MenuBarSection.Name,
        appState: AppState
    ) {
        guard source != target, !members.isEmpty else { return }
        let undoManager = appState.layoutUndo
        let tags = members.map(\.tag)
        undoManager.registerUndo(withTarget: appState) { appState in
            let current = tags.compactMap { appState.itemManager.managedItem(withTag: $0) }
            guard appState.menuBarManager.setSection(source, items: current, atomically: true) == nil else { return }
            registerGroupUndo(of: current, from: target, to: source, appState: appState)
        }
        undoManager.setActionName(String(localized: "Move Group"))
    }

    /// Undo for moving several ungrouped items into one section: each goes back to the section it came from.
    /// The inverse is registered inside the undo, so it lands as the redo rather than as a new edit.
    static func registerMoves(
        back restoring: [MenuBarSection.Name: [MenuBarItemTag]],
        forward: [MenuBarSection.Name: [MenuBarItemTag]],
        appState: AppState
    ) {
        // An item already where it was going has nothing to go back to.
        let restoring = restoring.filter { forward[$0.key] == nil && !$0.value.isEmpty }
        let moved = Set(restoring.values.joined())
        let forward = forward.mapValues { $0.filter(moved.contains) }.filter { !$0.value.isEmpty }
        guard !restoring.isEmpty else { return }
        let undoManager = appState.layoutUndo
        undoManager.registerUndo(withTarget: appState) { appState in
            registerMoves(back: forward, forward: restoring, appState: appState)
            for (section, tags) in restoring {
                let items = tags.compactMap { appState.itemManager.managedItem(withTag: $0) }
                MenuBarSearchItemActions.move(items, to: section, appState: appState)
            }
        }
        undoManager.setActionName(LayoutBatchMoveUndo.actionName(count: moved.count))
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
