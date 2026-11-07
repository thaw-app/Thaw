//
//  SearchEmptyStates.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ThawUI

extension ThawEmptyState {
    /// A query that matches nothing, with a way to start over.
    static func noSearchMatches(clear: @escaping () -> Void) -> ThawEmptyState {
        ThawEmptyState(
            systemImage: "magnifyingglass",
            title: "No items match",
            caption: "Try part of the item's name or the app that owns it.",
            actionTitle: "Clear Search",
            action: clear
        )
    }
}
