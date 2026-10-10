//
//  SearchIndex+Layout.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Layout Settings

    static let layoutEntries: [SearchEntry] = [
        SearchEntry(
            id: "advanced.enableAlwaysHiddenSection",
            title: "Always Hidden",
            descriptionText: String(localized: "Adds a third section for items you rarely need. They stay out of sight when you show your Hidden items."),
            pane: .menuBarLayout,
            section: "Sections",
            keywords: ["always hidden", "always-hidden", "section", "enable", "enable the always-hidden section"],
            property: .advanced("enableAlwaysHiddenSection")
        ),
        SearchEntry(
            id: "advanced.sectionDividerStyle",
            title: "Section divider style",
            descriptionText: nil,
            pane: .menuBarLayout,
            section: "Sections",
            keywords: ["divider", "style", "chevron", "separator", "section"],
            property: .advanced("sectionDividerStyle")
        ),
        SearchEntry(
            id: "layout.spacers",
            title: "Spacers",
            descriptionText: String(localized: "Insert empty gap items into the menu bar and adjust their width."),
            pane: .menuBarLayout,
            section: "Spacers",
            keywords: ["spacer", "gap", "space", "separator", "width"],
            property: nil
        ),
        SearchEntry(
            id: "layout.resetMenuBarLayout",
            title: "Reset menu bar layout",
            descriptionText: String(localized: "Moves every movable item except the \(Constants.displayName) icon to the selected section, just like a fresh install."),
            pane: .menuBarLayout,
            keywords: ["reset", "layout", "fresh", "visible", "hidden", "arrange"],
            property: nil
        ),
    ]
}
