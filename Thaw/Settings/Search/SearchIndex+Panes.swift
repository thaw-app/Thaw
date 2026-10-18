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
            id: "pane.widgets",
            title: "Widgets",
            descriptionText: nil,
            pane: .widgets,
            keywords: ["widgets", "widget", "glance", "custom icon", "combined icon", "battery", "wi-fi", "panel", "status menu"],
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
            pane: .displays,
            keywords: ["spaces", "space", "per-space", "desktop", "desktops", "fullscreen", "mission control", "hide", "reveal", "strip"],
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
            id: "profiles.shortcuts",
            title: "Profile shortcuts",
            descriptionText: String(localized: "Apply a profile with a keyboard shortcut."),
            pane: .profiles,
            section: "What switches to this profile",
            keywords: ["profile", "shortcut", "hotkey", "keyboard", "apply", "switch"],
            property: nil
        ),
        SearchEntry(
            id: "profiles.switching",
            title: "Switch profiles by display, Space or Focus",
            descriptionText: String(localized: "Choose a profile, then the display, Space or Focus that switches to it."),
            pane: .profiles,
            section: "What switches to this profile",
            keywords: ["switch", "automatic", "display", "space", "focus", "focus filter", "profile switching"],
            property: nil
        ),
        SearchEntry(
            id: "pane.scripts",
            title: "Scripts",
            descriptionText: String(localized: "Run scripts before and after a profile switches."),
            pane: .scripts,
            keywords: ["scripts", "scripting", "shell", "applescript", "hook", "automation", "profile switch"],
            property: nil
        ),
        SearchEntry(
            id: "privacy.otherApps",
            title: "Apps that change settings",
            descriptionText: String(localized: "Apps you approve can change settings with thaw:// links."),
            pane: .privacy,
            keywords: ["url", "scheme", "thaw://", "other apps", "allow", "approve", "xpc"],
            property: nil
        ),
        SearchEntry(
            id: "pane.triggers",
            title: "Triggers",
            descriptionText: String(localized: "Show menu bar items while an app is running."),
            pane: .triggers,
            keywords: ["trigger", "app running", "launch", "quit", "conditional", "show", "reveal", "rules", "automation"],
            property: nil
        ),
        SearchEntry(
            id: "pane.tools",
            title: "Troubleshooting",
            descriptionText: nil,
            pane: .tools,
            keywords: ["tools", "diagnostics", "logging", "logs", "reset", "cache", "permissions", "control center", "troubleshoot"],
            property: nil
        ),
        SearchEntry(
            id: "pane.modules",
            title: "Modules",
            descriptionText: "Optional parts of Thaw that run as their own apps.",
            pane: .modules,
            keywords: ["module", "modules", "extension", "add-on", "plugin", "automation", "scripts", "optional"],
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
