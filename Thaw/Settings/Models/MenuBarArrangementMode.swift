//
//  MenuBarArrangementMode.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// macOS 27 prefers granted TrailingItemPreferredPositions writes over synthetic drags, which hold physical mouse input.
/// Manual mode preserves user Command-drag order: Thaw moves or writes an item only for an explicit Layout edit.
nonisolated enum MenuBarArrangementMode: Int, CaseIterable, Identifiable {
    /// Layout drops, profiles, and saved order move real items.
    case automatic = 0
    /// Thaw never moves an item on its own. You arrange the bar with ⌘-drag or in Layout;
    /// Thaw records what it observes and moves only what a Layout edit asks for.
    case manual = 1

    var id: Int {
        rawValue
    }

    var localized: LocalizedStringKey {
        switch self {
        case .automatic: "Automatic"
        case .manual: "Manual"
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .automatic:
            "Thaw keeps items in the order you set in Layout. To move another app’s item it sometimes has to drag it for you, and your mouse is briefly unavailable while it does."
        case .manual:
            "You set the order yourself by ⌘-dragging items in the menu bar. Thaw still hides and shows items, but only moves an item when you arrange it in Layout."
        }
    }

    /// Whether Thaw may move items and write preferred positions on its own in this mode.
    /// False still leaves explicit Layout edits; see ExplicitLayoutEdit.
    var permitsOrderEnforcement: Bool {
        self == .automatic
    }
}
