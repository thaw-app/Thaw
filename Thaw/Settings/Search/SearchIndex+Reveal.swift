//
//  SearchIndex+Reveal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Reveal Settings

    /// Reveal and rehide controls live on the Visibility pane, so their search
    /// entries route to .visibility. The property: links are unchanged.
    static let revealEntries: [SearchEntry] = [
        SearchEntry(
            id: "visibility.showOnHoverDelay",
            title: "Hover delay",
            descriptionText: String(localized: "How long the pointer rests on the menu bar before hidden items show."),
            pane: .visibility,
            section: "Reveal hidden items",
            keywords: ["hover", "delay", "wait", "pointer"],
            property: .visibility("showOnHoverDelay")
        ),
        SearchEntry(
            id: "visibility.tooltipDelay",
            title: "Name delay",
            descriptionText: String(localized: "How long the pointer rests on an item before its name shows."),
            pane: .visibility,
            section: "On hover",
            keywords: ["tooltip", "name", "delay", "hover"],
            property: .visibility("tooltipDelay")
        ),
        SearchEntry(
            id: "visibility.swapOnThawIconClick",
            title: "Click the Thaw icon to swap",
            descriptionText: String(localized: "A click on the icon trades your shown and hidden items."),
            pane: .visibility,
            section: "Swap shown and hidden",
            keywords: ["swap", "click", "icon", "trade"],
            property: .visibility("swapOnThawIconClick")
        ),
        SearchEntry(
            id: "visibility.enableRecordingWatch",
            title: "Camera and microphone alerts",
            descriptionText: String(localized: "A short notice when the camera or microphone turns on."),
            pane: .visibility,
            section: "Zen Mode",
            keywords: ["camera", "microphone", "alert", "notice", "recording", "call"],
            property: .visibility("enableRecordingWatch")
        ),
        SearchEntry(
            id: "general.showOnClick",
            title: "Show on click",
            descriptionText: String(localized: "Click an empty area of the menu bar to show hidden menu bar items."),
            pane: .visibility,
            section: "Reveal hidden items",
            keywords: ["click", "show", "hidden"],
            property: .visibility("showOnClick")
        ),
        SearchEntry(
            id: "advanced.showAlwaysHiddenOnIconDoubleClick",
            title: "Double-click Thaw icon",
            descriptionText: String(localized: "Double-click the \(Constants.displayName) icon to show Always Hidden items."),
            pane: .visibility,
            section: "Reveal hidden items",
            keywords: ["double-click", "double click", "icon", "always hidden", "reveal"],
            property: .visibility("showAlwaysHiddenOnIconDoubleClick")
        ),
        SearchEntry(
            id: "advanced.enableSwapBar",
            title: "Show Swap Bar",
            descriptionText: String(localized: "A strip under the menu bar that trades your shown and hidden items in one click."),
            pane: .visibility,
            section: "Swap shown and hidden",
            keywords: ["swap", "switch", "exchange", "groups", "shown", "hidden", "bar", "strip", "floating", "controls", "profile", "zen", "toggle", "top", "menu bar", "right-click", "transport"],
            property: .visibility("enableSwapBar")
        ),
        SearchEntry(
            id: "general.showOnHover",
            title: "Show on hover",
            descriptionText: String(localized: "Hover over an empty area of the menu bar or the \(Constants.displayName) icon to show hidden menu bar items."),
            pane: .visibility,
            section: "Reveal hidden items",
            keywords: ["hover", "show", "hidden", "mouse"],
            property: .visibility("showOnHover")
        ),
        SearchEntry(
            id: "general.showOnScroll",
            title: "Show on scroll",
            descriptionText: String(localized: "Scroll or swipe in the menu bar to show hidden menu bar items."),
            pane: .visibility,
            section: "Reveal hidden items",
            keywords: ["scroll", "swipe", "show", "hidden", "gesture"],
            property: .visibility("showOnScroll")
        ),
        SearchEntry(
            id: "general.autoRehide",
            title: "Hide items again",
            descriptionText: String(localized: "Choose when hidden items you showed go away again: never, when you click elsewhere, when you switch apps, or after a delay."),
            pane: .visibility,
            section: "After revealing",
            keywords: [
                "rehide", "auto", "automatic", "automatically rehide", "hide", "never", "click elsewhere",
                "switch apps", "focus", "timed", "delay", "seconds", "minute", "strategy", "interval",
            ],
            property: .visibility("autoRehide")
        ),
        SearchEntry(
            id: "general.tempShowInterval",
            title: "Keep opened items in the menu bar for",
            descriptionText: String(localized: "How long a hidden menu bar item you open from search or the Thaw Bar stays in the menu bar before it hides again."),
            pane: .visibility,
            section: "After revealing",
            keywords: ["temp", "temporary", "temporarily shown", "show", "delay", "seconds", "hide again"],
            property: .visibility("tempShowInterval")
        ),
    ]
}
