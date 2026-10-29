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
            id: "displays.hiddenItemsPresentation",
            title: "Hidden items",
            descriptionText: String(localized: "Choose whether hidden items appear on click, in the \(Constants.displayName) Bar below the menu bar, or stay in the menu bar."),
            pane: .thawBar,
            keywords: [
                "ice bar", "thaw bar", "use thaw bar", "separate bar", "hidden",
                "always show hidden items", "always shown", "always", "show", "visible", "on click",
            ],
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
        SearchEntry(
            id: "displays.wideDisplayRule",
            title: "Show every item on wide displays",
            descriptionText: String(localized: "Keeps hidden items in the menu bar while it is on a display at least the width you choose."),
            pane: .displays,
            section: "Wide displays",
            keywords: ["wide", "large", "big", "external", "monitor", "screen size", "width", "show all", "every item"],
            property: nil
        ),
    ]
}
