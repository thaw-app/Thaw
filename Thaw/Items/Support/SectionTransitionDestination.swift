//
//  SectionTransitionDestination.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Where an item joining a section is placed.
///
/// Behind the predecessor when one was just seated, so a group keeps its
/// arrangement. Otherwise at the section's band boundary, beside the divider
/// that bounds it. The caller reads the live dividers and the setting and
/// passes plain values in.
nonisolated enum SectionTransitionDestination {
    static func destination(
        for section: MenuBarSection.Name,
        after predecessor: MenuBarItem?,
        hiddenDivider: MenuBarItem,
        alwaysHiddenDivider: MenuBarItem?,
        alwaysHiddenEnabled: Bool
    ) -> MoveDestination {
        let bandBoundary: MoveDestination = switch section {
        case .visible:
            .rightOfItem(hiddenDivider)
        case .hidden:
            if alwaysHiddenEnabled, let alwaysHiddenDivider {
                .rightOfItem(alwaysHiddenDivider)
            } else {
                .leftOfItem(hiddenDivider)
            }
        case .alwaysHidden:
            if let alwaysHiddenDivider {
                .leftOfItem(alwaysHiddenDivider)
            } else {
                .leftOfItem(hiddenDivider)
            }
        }
        return predecessor.map { .rightOfItem($0) } ?? bandBoundary
    }
}
