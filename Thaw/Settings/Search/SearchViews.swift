//
//  SearchViews.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Scrollable, grouped search results for the settings sidebar.
struct SearchResultsList: View {
    let groups: [SearchGroup]
    let onSelect: (SearchEntry) -> Void

    var body: some View {
        SettingsSearchResultsList(
            groups: groups,
            entries: \.entries,
            onSelect: onSelect,
            groupTitle: { Text($0.pane.localized) },
            result: { entry in
                SettingsSearchResultText(
                    title: Text(entry.titleKey),
                    section: entry.sectionKey.map { Text($0) },
                    detail: entry.descriptionText.map { Text($0) }
                )
            },
            // The same glyph the sidebar row shows, so a result group names its pane the way the sidebar does.
            groupIcon: { $0.pane.iconResource.image }
        )
    }
}

/// Empty state shown when a query returns no matches.
struct SearchEmptyView: View {
    /// The query that came up empty, quoted back so the reader can see
    /// what was actually searched, typos included.
    var query: String = ""

    var body: some View {
        NoMatchesState(
            query: query,
            title: { "No settings match “\($0)”" },
            emptyQueryTitle: "No settings found",
            caption: "Try a shorter or broader term."
        )
    }
}
