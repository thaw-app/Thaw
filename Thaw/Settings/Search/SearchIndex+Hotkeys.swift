//
//  SearchIndex+Hotkeys.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Hotkey Settings

    /// Hotkey bindings are dictionary-based on HotkeysSettings, not simple
    /// @Published toggles, so they are not covered by the drift guard.
    static let hotkeyEntries: [SearchEntry] = [
        SearchEntry(
            id: "hotkeys.toggleHiddenSection",
            title: "Toggle the Hidden section",
            descriptionText: nil,
            pane: .hotkeys,
            section: "Menu bar sections",
            keywords: ["toggle", "hidden", "section", "hotkey", "shortcut"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.toggleAlwaysHiddenSection",
            title: "Toggle the Always Hidden section",
            descriptionText: nil,
            pane: .hotkeys,
            section: "Menu bar sections",
            keywords: ["toggle", "always hidden", "section", "hotkey", "shortcut"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.searchMenuBarItems",
            title: "Search menu bar items",
            descriptionText: nil,
            pane: .hotkeys,
            section: "Menu bar items",
            keywords: ["search", "menu bar items", "hotkey", "shortcut", "panel"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.openMenuBarItems",
            title: "Open menu bar items",
            descriptionText: nil,
            pane: .hotkeys,
            section: "Menu bar items",
            keywords: ["open", "menu bar items", "hotkey", "per item"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.enableThawBar",
            titleKey: "Turn \(Constants.displayName) Bar on or off",
            titleText: "Turn \(Constants.displayName) Bar on or off",
            descriptionText: nil,
            pane: .hotkeys,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["enable", "toggle", "turn on", "turn off", "ice bar", "thaw bar", "hotkey", "shortcut", "keyboard shortcut"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.toggleApplicationMenus",
            title: "Toggle application menus",
            descriptionText: nil,
            pane: .hotkeys,
            section: "Other",
            keywords: ["toggle", "application menus", "app menus", "hotkey", "shortcut"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.toggleAutoRehide",
            title: "Toggle automatic rehiding",
            descriptionText: nil,
            pane: .hotkeys,
            section: "Other",
            keywords: ["toggle", "auto rehide", "automatically rehide", "hotkey", "shortcut"],
            property: nil
        ),
    ]
}
