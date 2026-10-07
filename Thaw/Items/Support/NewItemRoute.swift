//
//  NewItemRoute.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// How a newly arrived item reaches the section the New Items setting names.
nonisolated enum NewItemRoute: Equatable {
    /// Assign the section. The section change seats the item itself.
    case assign
    /// Move the item beside the anchor the setting names.
    case move

    /// A concealed section's default slot is beside a divider, and macOS 27 refuses a move aimed at one.
    /// Such a newcomer is assigned its section instead, or it would stay Visible.
    init(section: MenuBarSectionName, destinationIsDivider: Bool) {
        self = section != .visible && destinationIsDivider ? .assign : .move
    }
}
