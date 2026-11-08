//
//  LayoutItemVisibility.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// The Layout window list's checkbox: checked is Visible, unchecked is Hidden or Always Hidden.
@MainActor
enum LayoutItemVisibility {
    static func isShown(_ section: MenuBarSectionName) -> Bool {
        section == .visible
    }

    /// Why the checkbox can't change, or nil when it can. The same test the bars use to lock a glyph.
    static func lockReason(for item: MenuBarItem, in section: MenuBarSectionName, experimentalSystemItemHiding: Bool) -> String? {
        if item.isControlItem || !item.isMovable(experimentalSystemItemHiding: experimentalSystemItemHiding) {
            return String(localized: "macOS keeps this item in place, so it can’t be hidden.")
        }
        if isShown(section), !item.canBeHidden {
            return String(localized: "macOS keeps this item shown, so it can’t be hidden.")
        }
        return nil
    }

    /// Shows or hides the row's item, or every selected item when the row is one of several,
    /// through the bars' move path so refusals and undo match a drag.
    static func setShown(
        _ shown: Bool,
        rowID: String,
        in section: MenuBarSectionName,
        selection: LayoutSelectionModel,
        appState: AppState
    ) {
        if !(selection.count > 1 && selection.contains(rowID)) {
            selection.click(rowID, in: section, kind: .replace)
        }
        moveSelection(to: shown ? .visible : .hidden, selection: selection, appState: appState)
    }

    /// Moves the selection to section, beside its divider so the rest of the bar keeps its order.
    static func moveSelection(to section: MenuBarSectionName, selection: LayoutSelectionModel, appState: AppState) {
        LayoutSelectionActions(selection: selection, appState: appState)
            .move(to: section, placement: section == .visible ? .start : .end)
    }
}
