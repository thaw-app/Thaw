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
            descriptionText: String(localized: "Shows only the essential settings, with a preview of your sections. Everything else keeps working as you set it."),
            pane: .general,
            keywords: ["simple", "mode", "basic", "essential", "minimal", "advanced", "hide", "drag"],
            property: .general("simpleMode")
        ),
        SearchEntry(
            id: "general.lockThawBarPosition",
            titleKey: "Lock \(Constants.displayName) Bar position",
            titleText: "Lock \(Constants.displayName) Bar position",
            descriptionText: String(localized: "Keeps the \(Constants.displayName) Bar where it opens. Turn off to drag it by its background."),
            pane: .thawBar,
            sectionKey: "Options for all displays",
            sectionText: "Options for all displays",
            keywords: ["lock", "drag", "move", "pin", "bar", "position"],
            property: .thawBar("lockThawBarPosition")
        ),
        SearchEntry(
            id: "general.showDockIconWithSettings",
            title: "Show Dock icon while Settings is open",
            descriptionText: String(localized: "Off, Thaw stays out of the Dock and its recent apps."),
            pane: .general,
            section: "App",
            keywords: ["dock", "icon", "recent apps", "app switcher"],
            property: .general("showDockIconWithSettings")
        ),
        SearchEntry(
            id: "general.showSettingDescriptions",
            title: "Show setting descriptions",
            descriptionText: String(localized: "Explains what a setting does directly beneath it."),
            pane: .general,
            section: "Language and theme",
            keywords: ["descriptions", "captions", "details", "help", "annotations", "explanations"],
            property: .general("showSettingDescriptions")
        ),
        SearchEntry(
            id: "general.settingsAppearance",
            title: "Settings theme",
            descriptionText: String(localized: "Applies to Settings and onboarding. Black suits OLED displays."),
            pane: .general,
            section: "Language and theme",
            keywords: ["appearance", "theme", "system", "match", "macos", "automatic", "light", "dark", "dark mode", "black", "oled", "background"],
            property: .general("settingsAppearance")
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
            title: "When opened by a shortcut",
            descriptionText: String(localized: "Choose whether a shortcut opens the \(Constants.displayName) Bar where Location says or centered on the pointer."),
            pane: .thawBar,
            keywords: ["ice bar", "thaw bar", "mouse", "pointer", "hotkey", "shortcut", "keyboard", "location", "show at mouse pointer"],
            property: .thawBar("thawBarLocationOnHotkey")
        ),
        SearchEntry(
            id: "general.openHiddenItemsInMenuBar",
            title: "Show clicked items in the menu bar",
            descriptionText: String(localized: "When you open a hidden item from the \(Constants.displayName) Bar or search, \(Constants.displayName) shows it in the menu bar and opens its menu under its icon."),
            pane: .thawBar,
            section: "Options for all displays",
            keywords: ["ice bar", "thaw bar", "click", "open", "menu", "reveal", "show", "hidden", "open hidden items in the menu bar"],
            property: .thawBar("openHiddenItemsInMenuBar")
        ),
    ]
}
