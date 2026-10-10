//
//  SearchIndex+Reveal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Reveal Settings

    /// Reveal/rehide/icon-gesture/rearranging controls now live on the Menu
    /// Bar destination's Access surface, so their search entries route to
    /// .menuBarLayout. The property: links are unchanged.
    static let revealEntries: [SearchEntry] = [
        SearchEntry(
            id: "general.showOnClick",
            title: "Show on click",
            descriptionText: String(localized: "Click an empty area of the menu bar to show hidden menu bar items."),
            pane: .visibility,
            section: "Reveal hidden items",
            keywords: ["click", "show", "hidden"],
            property: .general("showOnClick")
        ),
        SearchEntry(
            id: "advanced.enableSwapBar",
            title: "Show Swap Bar",
            descriptionText: String(localized: "A strip under the menu bar that trades your shown and hidden items in one click."),
            pane: .visibility,
            section: "Swap shown and hidden",
            keywords: ["swap", "switch", "exchange", "groups", "shown", "hidden", "bar", "strip", "floating", "controls", "profile", "zen", "toggle", "top", "menu bar", "right-click", "transport"],
            property: .advanced("enableSwapBar")
        ),
        SearchEntry(
            id: "general.showOnHover",
            title: "Show on hover",
            descriptionText: String(localized: "Hover over an empty area of the menu bar to show hidden menu bar items."),
            pane: .visibility,
            section: "Reveal hidden items",
            keywords: ["hover", "show", "hidden", "mouse"],
            property: .general("showOnHover")
        ),
        SearchEntry(
            id: "general.showOnScroll",
            title: "Show on scroll",
            descriptionText: String(localized: "Scroll or swipe in the menu bar to show hidden menu bar items."),
            pane: .visibility,
            section: "Reveal hidden items",
            keywords: ["scroll", "swipe", "show", "hidden", "gesture"],
            property: .general("showOnScroll")
        ),
        SearchEntry(
            id: "general.autoRehide",
            title: "Automatically rehide",
            descriptionText: nil,
            pane: .visibility,
            section: "After revealing",
            keywords: ["rehide", "auto", "automatic", "hide"],
            property: .general("autoRehide")
        ),
        SearchEntry(
            id: "general.tempShowInterval",
            title: "Hide again after",
            descriptionText: String(localized: "How long a hidden menu bar item you open from search or the Thaw Bar stays in the menu bar."),
            pane: .visibility,
            section: "After revealing",
            keywords: ["temp", "temporary", "temporarily shown", "show", "delay", "seconds", "hide again"],
            property: .general("tempShowInterval")
        ),
    ]
}
