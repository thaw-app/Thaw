//
//  SearchListMove.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ThawUI

/// A key that moves the search list's highlight.
///
/// The panel's key monitor handles these instead of the list's onKeyPress,
/// which never sees the repeats of a held key.
nonisolated enum SearchListMove: Equatable {
    case up
    case down
    case pageUp
    case pageDown
    case home
    case end

    /// Selectable rows a Page Up or Page Down skips.
    static let pageLength = 8

    /// Nil for any other key, and for a key held with Shift, Option, Command
    /// or Control, which the query field uses to move and select text.
    init?(key: KeyCode, modifiers: Modifiers) {
        guard modifiers.isEmpty else {
            return nil
        }
        switch key {
        case .upArrow: self = .up
        case .downArrow: self = .down
        case .pageUp: self = .pageUp
        case .pageDown: self = .pageDown
        case .home: self = .home
        case .end: self = .end
        default: return nil
        }
    }

    /// The row this move highlights, clamped to the first and last
    /// selectable rows. With no highlight, or one that is no longer listed,
    /// any move starts at the first selectable row.
    func target<ID: Hashable>(from selection: ID?, in rows: [(id: ID, isSelectable: Bool)]) -> ID? {
        let selectable = rows.filter(\.isSelectable).map(\.id)
        guard let first = selectable.first else {
            return nil
        }
        guard let selection, let index = selectable.firstIndex(of: selection) else {
            return first
        }
        let target = switch self {
        case .up: index - 1
        case .down: index + 1
        case .pageUp: index - Self.pageLength
        case .pageDown: index + Self.pageLength
        case .home: 0
        case .end: selectable.count - 1
        }
        return selectable[min(max(target, 0), selectable.count - 1)]
    }
}

/// Keeps the search list's highlight on a row it actually lists.
nonisolated enum SearchListSelection {
    /// selection while it is still a selectable row, otherwise the first
    /// selectable row. Row IDs carry window IDs, so a rebuilt menu bar can
    /// leave a highlight that matches nothing, and the list ignores the
    /// arrows and Return until something is highlighted again.
    static func validated<ID: Hashable>(_ selection: ID?, in rows: [(id: ID, isSelectable: Bool)]) -> ID? {
        if let selection, rows.contains(where: { $0.id == selection && $0.isSelectable }) {
            return selection
        }
        return rows.first(where: \.isSelectable)?.id
    }
}

extension MenuBarSearchModel {
    private var rowSelectability: [(id: ItemID, isSelectable: Bool)] {
        displayedItems.map { (id: $0.id, isSelectable: $0.isSelectable) }
    }

    /// Highlights the topmost row that can actually be acted on.
    func selectFirstSelectableRow() {
        selection = displayedItems.first(where: \.isSelectable)?.id
    }

    /// Moves the highlight to the first row when the highlighted one is no
    /// longer listed, and leaves it alone otherwise.
    func revalidateSelection() {
        let validated = SearchListSelection.validated(selection, in: rowSelectability)
        if validated != selection {
            selection = validated
        }
    }

    /// Moves the highlight the way move asks. The list scrolls to it.
    func moveSelection(_ move: SearchListMove) {
        let target = move.target(from: selection, in: rowSelectability)
        if target != selection {
            selection = target
        }
    }
}
