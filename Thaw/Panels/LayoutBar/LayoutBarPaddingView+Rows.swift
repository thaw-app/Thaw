//
//  LayoutBarPaddingView+Rows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// A bar that wraps gives its items rows as wide as itself, less the inset on either side.
extension LayoutBarPaddingView {
    /// The room between the bar's edge and its items, on either side.
    static let itemInset: CGFloat = 7.5

    /// Gives the items rows as wide as a bar of width, less the inset on either side.
    func wrapRows(toWidth width: CGFloat) {
        guard wrapsRows else { return }
        container.rowWidth = max(1, width - Self.itemInset * 2)
    }

    /// How tall the bar's items stand at a width, before it lays out at that width.
    func wrappedItemsHeight(width: CGFloat) -> CGFloat {
        container.wrappedHeight(rowWidth: max(1, width - Self.itemInset * 2))
    }
}

/// Which items a drag on the bar may pick up and reorder.
extension LayoutBarPaddingView {
    /// Whether an item may be used as a layout-bar drag source on macOS 27.
    /// The visible Thaw control is a real movable status item; the zero-width
    /// divider controls remain structural and must never be reordered.
    static func acceptsLayoutDrag(of item: MenuBarItem) -> Bool {
        !item.isControlItem || item.tag.matchesVisibleControlItem
    }

    /// Whether anchored Apple system items may be freely reordered in the
    /// layout editor. Without Thaw Bar, hidden anchored items still mirror the
    /// real menu bar's trailing system-control placement.
    static func allowsAnchoredSystemItemReordering(appState: AppState?) -> Bool {
        guard let appState else {
            return false
        }
        if let displayID = appState.itemManager.itemDisplayID {
            return appState.settings.displaySettings.useThawBar(for: displayID)
        }
        return appState.settings.displaySettings.configurationForActiveDisplay().useThawBar
    }
}
