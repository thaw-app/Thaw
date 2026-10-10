//
//  SearchIndex+General.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: General Settings

    static let generalEntries: [SearchEntry] = [
        SearchEntry(
            id: "general.launchAtLogin",
            title: "Launch at Login",
            descriptionText: nil,
            pane: .general,
            keywords: ["launch", "login", "startup", "auto", "start"],
            property: nil
        ),
        SearchEntry(
            id: "general.simpleMode",
            title: "Simple Mode",
            descriptionText: String(localized: "Shows only the essential settings. All features keep working and keep their configuration."),
            pane: .general,
            keywords: ["simple", "mode", "basic", "essential", "minimal", "advanced", "hide"],
            property: .general("simpleMode")
        ),
        SearchEntry(
            id: "general.lockThawBarPosition",
            titleKey: "Lock \(Constants.displayName) Bar position",
            titleText: "Lock \(Constants.displayName) Bar position",
            descriptionText: String(localized: "Keep the \(Constants.displayName) Bar pinned in place instead of draggable."),
            pane: .thawBar,
            sectionKey: "Options for all displays",
            sectionText: "Options for all displays",
            keywords: ["lock", "drag", "move", "pin", "bar", "position"],
            property: .general("lockThawBarPosition")
        ),
        // Thaw Bar Only is unplugged for now; restore this with the gate in MenuBarItemManager+ThawBarOnly.swift.
        // SearchEntry(
        //     id: "general.enableThawBarOnly",
        //     titleKey: "Thaw Bar Only",
        //     titleText: "Thaw Bar Only",
        //     descriptionText: String(localized: "Items macOS won't show in the menu bar stay in the \(Constants.displayName) Bar. Turn this off to treat them as ordinary hidden items. Your list comes back when you turn it on again."),
        //     pane: .thawBar,
        //     sectionKey: "Options for all displays",
        //     sectionText: "Options for all displays",
        //     keywords: ["thaw bar only", "turn off", "disable", "not shown", "hidden"],
        //     property: .general("enableThawBarOnly")
        // ),
        // SearchEntry(
        //     id: "general.showThawBarOnlyWithInlineReveal",
        //     titleKey: "Show Thaw Bar Only items when showing hidden items",
        //     titleText: "Show Thaw Bar Only items when showing hidden items",
        //     descriptionText: String(localized: "When you show hidden items, the items kept in the \(Constants.displayName) Bar appear in a small \(Constants.displayName) Bar below the menu bar."),
        //     pane: .thawBar,
        //     sectionKey: "Options for all displays",
        //     sectionText: "Options for all displays",
        //     keywords: ["thaw bar only", "reveal", "inline", "hidden", "small bar", "companion", "not shown"],
        //     property: .general("showThawBarOnlyWithInlineReveal")
        // ),
        // SearchEntry(
        //     id: "general.showThawBarOnlyLauncher",
        //     titleKey: "Menu bar icon for Thaw Bar Only items",
        //     titleText: "Menu bar icon for Thaw Bar Only items",
        //     descriptionText: String(localized: "A menu bar icon that opens a small \(Constants.displayName) Bar with just the items macOS won't show in the menu bar."),
        //     pane: .thawBar,
        //     sectionKey: "Options for all displays",
        //     sectionText: "Options for all displays",
        //     keywords: ["thaw bar only", "launcher", "icon", "small bar", "not shown", "menu bar"],
        //     property: .general("showThawBarOnlyLauncher")
        // ),
        SearchEntry(
            id: "general.showSettingDescriptions",
            title: "Show setting descriptions",
            descriptionText: String(localized: "Explains what a setting does directly beneath it."),
            pane: .general,
            keywords: ["descriptions", "captions", "details", "help", "annotations", "explanations"],
            property: .general("showSettingDescriptions")
        ),
        SearchEntry(
            id: "general.showThawIcon",
            titleKey: "Show \(Constants.displayName) icon",
            titleText: "Show \(Constants.displayName) icon",
            descriptionText: String(localized: "Show the \(Constants.displayName) icon in the menu bar. Click to show hidden items, double-click for always-hidden, and right-click for settings."),
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["icon", "show", "menu bar", "status item"],
            property: .general("showThawIcon")
        ),
        SearchEntry(
            id: "general.thawIcon",
            titleKey: "\(Constants.displayName) icon",
            titleText: "\(Constants.displayName) icon",
            descriptionText: String(localized: "Choose a custom icon to show in the menu bar."),
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["icon", "picker", "custom", "image"],
            property: .general("thawIcon")
        ),
        SearchEntry(
            id: "general.customThawIconIsTemplate",
            title: "Custom icon uses dynamic appearance",
            descriptionText: String(localized: "Display the icon as a monochrome image that dynamically adjusts to match the menu bar's appearance."),
            pane: .general,
            keywords: ["template", "monochrome", "dark mode", "custom icon"],
            property: .general("customThawIconIsTemplate")
        ),
        SearchEntry(
            id: "general.thawBarLocationOnHotkey",
            title: "Show at mouse pointer from a keyboard shortcut",
            descriptionText: String(localized: "Always show the \(Constants.displayName) Bar at the mouse pointer when a keyboard shortcut opens it."),
            pane: .thawBar,
            section: "Options for all displays",
            keywords: ["ice bar", "thaw bar", "mouse", "pointer", "hotkey", "location"],
            property: .general("thawBarLocationOnHotkey")
        ),
        SearchEntry(
            id: "general.openHiddenItemsInMenuBar",
            title: "Open hidden items in the menu bar",
            descriptionText: String(localized: "Clicking a hidden item shows it in the menu bar and opens its menu under the icon. Turn off to open the menu without showing the icon."),
            pane: .thawBar,
            section: "Options for all displays",
            keywords: ["ice bar", "thaw bar", "click", "open", "menu", "reveal", "show", "hidden"],
            property: .general("openHiddenItemsInMenuBar")
        ),
    ]
}
