//
//  LayoutEditUndo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Undo for layout edits that aren't moves: grouping, folders, item names and icons.
/// Each registers a redo when undone, so redo always works.
@MainActor
enum LayoutEditUndo {
    /// Runs edit, then registers an undo that puts the groups back as they were.
    static func editGroups(
        _ actionName: String,
        manager: MenuBarItemGroupManager,
        undoManager: UndoManager?,
        edit: () -> Void
    ) {
        let before = manager.snapshot()
        edit()
        let after = manager.snapshot()
        guard let undoManager, after != before else { return }
        registerGroups(restoring: before, redoing: after, actionName: actionName, manager: manager, undoManager: undoManager)
    }

    private static func registerGroups(
        restoring old: MenuBarItemGroupSet,
        redoing new: MenuBarItemGroupSet,
        actionName: String,
        manager: MenuBarItemGroupManager,
        undoManager: UndoManager
    ) {
        undoManager.registerUndo(withTarget: manager) { [weak undoManager] manager in
            manager.apply(old)
            guard let undoManager else { return }
            registerGroups(restoring: new, redoing: old, actionName: actionName, manager: manager, undoManager: undoManager)
        }
        undoManager.setActionName(actionName)
    }

    /// Shows or stops showing a group as a folder; undo flips it back.
    static func setFolder(
        _ isFolder: Bool,
        for origin: MenuBarItemGroupOrigin,
        members: [MenuBarItem],
        name: String,
        folders: GroupFolders,
        undoManager: UndoManager?
    ) {
        guard folders.isFolder(origin) != isFolder else { return }
        folders.setFolder(isFolder, for: origin, members: members)
        // setFolder does nothing for a group it can't resolve; then there's nothing to undo.
        guard folders.isFolder(origin) == isFolder else { return }
        undoManager?.registerUndo(withTarget: folders) { [weak undoManager] folders in
            setFolder(!isFolder, for: origin, members: members, name: name, folders: folders, undoManager: undoManager)
        }
        undoManager?.setActionName(String(localized: "Folder Setting for \(name)", comment: "Undo menu action name for showing a group as a folder or not"))
    }

    /// Renames an item; nil or empty restores the name its app gives it.
    static func rename(_ item: MenuBarItem, to name: String?, undoManager: UndoManager?) {
        let old = item.customName
        guard old != name else { return }
        var item = item
        item.customName = name
        undoManager?.registerUndo(withTarget: MenuBarItemIconChoices.shared) { [weak undoManager] _ in
            rename(item, to: old, undoManager: undoManager)
        }
        undoManager?.setActionName(String(localized: "Rename Item", comment: "Undo menu action name for renaming a menu bar item"))
    }

    /// Sets or clears an item's chosen icon; undo restores the previous choice.
    static func setIcon(_ image: NSImage?, for item: MenuBarItem, undoManager: UndoManager?) {
        let choices = MenuBarItemIconChoices.shared
        let old = choices.hasChoice(for: item) ? choices.image(for: item) : nil
        choices.setImage(image, for: item)
        undoManager?.registerUndo(withTarget: choices) { [weak undoManager] _ in
            setIcon(old, for: item, undoManager: undoManager)
        }
        undoManager?.setActionName(String(localized: "Change Icon", comment: "Undo menu action name for choosing a menu bar item's icon"))
    }
}
