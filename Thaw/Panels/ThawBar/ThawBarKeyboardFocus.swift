//
//  ThawBarKeyboardFocus.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation

/// Which Thaw Bar item the keyboard has highlighted, when a keyboard
/// shortcut opened the bar.
///
/// The panel takes key focus only then, so the arrow keys move this
/// highlight instead of reaching the frontmost app, and Return or Space
/// clicks the highlighted item. Opened by a click, the bar never takes focus
/// and index stays nil.
@MainActor
@Observable
final class ThawBarKeyboardFocus {
    /// How the arrow keys map onto the layout.
    enum Arrangement: Equatable {
        /// One row: left and right move; up and down do nothing.
        case row
        /// One column: every arrow moves one item.
        case column
        /// Rows of this many items: left and right move one, up and down one row.
        case grid(columns: Int)
    }

    /// The highlighted item's position among the bar's items.
    private(set) var index: Int?

    /// Bumped when Return or Space asks the highlighted item to click.
    private(set) var activationRequest = 0

    private var itemCount = 0
    private var arrangement = Arrangement.row

    /// Starts keyboard use: highlights the first item.
    func begin() {
        index = itemCount > 0 ? 0 : nil
    }

    /// Ends keyboard use.
    func end() {
        index = nil
    }

    /// Keeps the highlight inside the current items after they change.
    func update(itemCount: Int, arrangement: Arrangement) {
        self.itemCount = itemCount
        self.arrangement = arrangement
        guard let index else { return }
        self.index = itemCount > 0 ? min(index, itemCount - 1) : nil
    }

    /// Moves the highlight. dx is -1 or 1 for left and right, dy for up
    /// and down.
    func move(dx: Int, dy: Int) {
        guard itemCount > 0, let index else { return }
        let step = switch arrangement {
        case .row: dx
        case .column: dx + dy
        case let .grid(columns): dx + dy * max(1, columns)
        }
        guard step != 0 else { return }
        self.index = min(itemCount - 1, max(0, index + step))
    }

    /// The pointer moved onto an item: the highlight follows it, so only one
    /// item is ever marked and the arrow keys carry on from where the pointer
    /// is. Does nothing while the keyboard is not in use.
    func pointerEntered(_ newIndex: Int) {
        guard index != nil, newIndex >= 0, newIndex < itemCount else { return }
        index = newIndex
    }

    /// Asks the highlighted item to click.
    func activate() {
        guard index != nil else { return }
        activationRequest += 1
    }
}
