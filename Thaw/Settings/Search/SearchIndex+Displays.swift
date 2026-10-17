//
//  SearchIndex+Displays.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Display Settings

    /// Display settings are configuration-based (per-display and global
    /// templates on DisplaySettingsManager), not direct @Published toggles,
    /// so they are not covered by the drift guard. They are indexed for search
    /// discoverability.
    static let displayEntries: [SearchEntry] = [
        SearchEntry(
            id: "displays.useThawBar",
            titleKey: "Use \(Constants.displayName) Bar",
            titleText: "Use \(Constants.displayName) Bar",
            descriptionText: String(localized: "Show hidden menu bar items in a separate bar below the menu bar."),
            pane: .thawBar,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["ice bar", "thaw bar", "hidden", "separate bar"],
            property: nil
        ),
        SearchEntry(
            id: "displays.alwaysShowHiddenItems",
            title: "Always show hidden items",
            descriptionText: String(localized: "Always show hidden menu bar items in the menu bar. Not available on a display that uses the \(Constants.displayName) Bar."),
            pane: .thawBar,
            keywords: ["always", "show", "hidden", "visible"],
            property: nil
        ),
        SearchEntry(
            id: "displays.thawBarLocation",
            titleKey: "Location",
            titleText: "\(Constants.displayName) Bar location",
            descriptionText: String(localized: "The \(Constants.displayName) Bar's location changes based on context."),
            pane: .thawBar,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["ice bar", "thaw bar", "location", "mouse", "aligned"],
            property: nil
        ),
        SearchEntry(
            id: "displays.thawBarLayout",
            titleKey: "Arrangement",
            titleText: "\(Constants.displayName) Bar arrangement",
            descriptionText: String(localized: "Items are arranged in a single horizontal row, stacked vertically, or in a grid."),
            pane: .thawBar,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["ice bar", "thaw bar", "layout", "arrangement", "horizontal", "vertical", "grid", "columns"],
            property: nil
        ),
        SearchEntry(
            id: "displays.itemSpacing",
            title: "Menu bar item spacing",
            descriptionText: String(localized: "Applying briefly relaunches apps with menu bar items so they pick up the new spacing."),
            pane: .displays,
            section: "Menu bar item spacing",
            keywords: ["spacing", "padding", "menu bar", "items", "gap"],
            property: nil
        ),
        SearchEntry(
            id: "displays.spacingApplyMode",
            title: "When spacing changes",
            descriptionText: String(localized: "Choose whether a spacing change asks first, restarts menu bar apps right away, or waits until they restart."),
            pane: .displays,
            section: "Menu bar item spacing",
            keywords: ["spacing", "confirm", "relaunch", "restart", "apps", "without", "immediate", "next restart", "when applying spacing"],
            property: nil
        ),
    ]
}
