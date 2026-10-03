//
//  SearchIndex+Panes.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Pane Rows

    static let paneEntries: [SearchEntry] = [
        SearchEntry(
            id: "pane.general",
            title: "General",
            descriptionText: nil,
            pane: .general,
            keywords: ["general", "launch", "startup", "login", "icon", "reveal", "show", "hide", "hover", "click", "scroll", "rehide", "gesture"],
            property: nil
        ),
        SearchEntry(
            id: "pane.privacy",
            title: "Privacy",
            descriptionText: nil,
            pane: .privacy,
            keywords: ["privacy", "permissions", "accessibility", "screen recording", "network", "what thaw sees", "data", "tracking", "analytics"],
            property: nil
        ),
        SearchEntry(
            id: "pane.menuBarLayout",
            title: "Layout",
            descriptionText: nil,
            pane: .menuBarLayout,
            keywords: ["layout", "arrange", "drag", "reorder", "sections", "reset", "overflow", "system items", "always hidden", "divider"],
            property: nil
        ),
        SearchEntry(
            id: "pane.scripts",
            title: "Scripts",
            descriptionText: nil,
            pane: .scripts,
            keywords: ["scripts", "script", "custom", "module", "plugin", "command"],
            property: nil
        ),
        SearchEntry(
            id: "pane.widgets",
            title: "Widgets",
            descriptionText: nil,
            pane: .widgets,
            keywords: ["widgets", "widget", "control center", "notification center", "glance", "icon builder", "custom icon", "combined icon", "arc", "ring", "dots", "sample readings"],
            property: nil
        ),
        SearchEntry(
            id: "pane.theLab",
            title: "Experiments",
            descriptionText: nil,
            pane: .theLab,
            keywords: ["lab", "experiments", "experimental", "alpha", "beta", "preview", "try"],
            property: nil
        ),
        SearchEntry(
            id: "pane.displays",
            title: "Displays",
            descriptionText: nil,
            pane: .displays,
            keywords: ["display", "monitor", "screen", "notch", "spacing", "ice bar", "thaw bar", "arrangement"],
            property: nil
        ),
        SearchEntry(
            id: "pane.thawBar",
            titleKey: "\(Constants.displayName) Bar",
            titleText: "\(Constants.displayName) Bar",
            descriptionText: String(localized: "Turn the \(Constants.displayName) Bar on per display, choose its layout, and set where it opens."),
            pane: .thawBar,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["ice bar", "thaw bar", "hidden", "separate bar", "layout", "horizontal", "vertical", "grid", "placement", "location", "dedicated bar"],
            property: nil
        ),
        SearchEntry(
            id: "pane.spaces",
            title: "Spaces",
            descriptionText: nil,
            pane: .spaces,
            keywords: ["spaces", "space", "per-space", "desktop", "fullscreen", "mission control", "hide", "reveal", "strip"],
            property: nil
        ),
        SearchEntry(
            id: "pane.menuBarAppearance",
            title: "Appearance",
            descriptionText: nil,
            pane: .menuBarAppearance,
            keywords: ["appearance", "tint", "color", "shadow", "border", "shape", "background", "dark mode", "fill", "glass"],
            property: nil
        ),
        SearchEntry(
            id: "pane.hotkeys",
            title: "Shortcuts",
            descriptionText: nil,
            pane: .hotkeys,
            keywords: ["hotkey", "shortcut", "keyboard", "toggle", "search"],
            property: nil
        ),
        SearchEntry(
            id: "pane.profiles",
            title: "Profiles",
            descriptionText: nil,
            pane: .profiles,
            keywords: ["profile", "preset", "layout", "snapshot"],
            property: nil
        ),
        SearchEntry(
            id: "pane.automation",
            title: "Rules",
            descriptionText: nil,
            pane: .automation,
            keywords: ["rules", "automation", "url", "scheme", "scripting", "xpc"],
            property: nil
        ),
        SearchEntry(
            id: "pane.triggers",
            title: "Triggers",
            descriptionText: "Show menu bar items while an app is running.",
            pane: .triggers,
            keywords: ["trigger", "app running", "launch", "quit", "conditional", "show", "reveal"],
            property: nil
        ),
        SearchEntry(
            id: "pane.tools",
            title: "Tools",
            descriptionText: nil,
            pane: .tools,
            keywords: ["tools", "diagnostics", "logging", "logs", "reset", "cache", "permissions", "control center", "troubleshoot"],
            property: nil
        ),
        SearchEntry(
            id: "pane.about",
            title: "About",
            descriptionText: nil,
            pane: .about,
            keywords: ["about", "version", "update", "credits", "license"],
            property: nil
        ),
    ]
}
