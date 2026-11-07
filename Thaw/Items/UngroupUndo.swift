//
//  UngroupUndo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Ungroup with an undo that brings the group back, with its name and, if it was one, its folder.
@MainActor
enum UngroupUndo {
    static func ungroup(
        _ origin: MenuBarItemGroupOrigin,
        name: String,
        manager: MenuBarItemGroupManager,
        folders: GroupFolders?,
        undoManager: UndoManager?
    ) {
        let previous = manager.groupSet
        let folderID: UUID? = if case let .user(id) = origin, folders?.isFolder(origin) == true { id } else { nil }
        manager.ungroup(origin)
        guard let undoManager, manager.groupSet != previous else { return }
        undoManager.registerUndo(withTarget: manager) { [weak folders, weak undoManager] manager in
            manager.apply(previous)
            if let folderID {
                folders?.restoreFolder(folderID)
            }
            undoManager?.registerUndo(withTarget: manager) { [weak folders] manager in
                ungroup(origin, name: name, manager: manager, folders: folders, undoManager: undoManager)
            }
            undoManager?.setActionName(actionName(name))
        }
        undoManager.setActionName(actionName(name))
    }

    nonisolated static func actionName(_ name: String) -> String {
        String(localized: "Ungroup \(name)", comment: "Undo menu action name for ungrouping a menu bar item group")
    }
}
