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
            titleKey: "\(Constants.displayName) Bar",
            titleText: "\(Constants.displayName) Bar",
            descriptionText: String(localized: "When on, hidden items appear in the \(Constants.displayName) Bar below the menu bar."),
            pane: .thawBar,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["ice bar", "thaw bar", "use thaw bar", "separate bar", "hidden", "turn on", "turn off", "off"],
            property: nil
        ),
        SearchEntry(
            id: "displays.alwaysShowHiddenItems",
            title: "Always show hidden items",
            descriptionText: String(localized: "Hidden items stay in the menu bar instead of waiting for you to reveal them. Has no effect while the \(Constants.displayName) Bar is on."),
            pane: .thawBar,
            keywords: ["always", "show", "hidden", "visible", "always shown", "menu bar", "inline"],
            property: nil
        ),
        SearchEntry(
            id: "displays.useThawBarForAlwaysHidden",
            title: "Open Always Hidden in the \(Constants.displayName) Bar",
            descriptionText: String(localized: "Hidden items still show in the menu bar. Showing Always Hidden there would open Hidden too."),
            pane: .thawBar,
            keywords: ["always hidden", "ice bar", "thaw bar", "only", "section"],
            property: nil
        ),
        SearchEntry(
            id: "displays.thawBarLocation",
            titleKey: "Location",
            titleText: "\(Constants.displayName) Bar location",
            descriptionText: String(localized: "Where the \(Constants.displayName) Bar opens: under the pointer, under the \(Constants.displayName) icon, or at the left or right edge of the display."),
            pane: .thawBar,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["ice bar", "thaw bar", "location", "mouse", "pointer", "aligned", "edge", "dynamic", "icon"],
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
            id: "displays.thawBarItemSize",
            titleKey: "Item size",
            titleText: "\(Constants.displayName) Bar item size",
            descriptionText: String(localized: "How large items are in the \(Constants.displayName) Bar. At 100% they match the menu bar; smaller sizes fit more items in a row."),
            pane: .thawBar,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["ice bar", "thaw bar", "item size", "icon size", "scale", "smaller", "compact", "zoom"],
            property: nil
        ),
        SearchEntry(
            id: "displays.itemSpacing",
            title: "Menu bar item spacing",
            descriptionText: String(localized: "The space between menu bar items on each display. Applying a change can restart apps with menu bar items."),
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
            id: "displays.template",
            title: "Template for new displays",
            descriptionText: String(localized: "The \(Constants.displayName) Bar settings and spacing new displays start with, and a button that applies them to every display."),
            pane: .displays,
            section: "Template for new displays",
            keywords: ["template", "global", "new displays", "all displays", "apply to all", "default", "customized", "use template"],
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
