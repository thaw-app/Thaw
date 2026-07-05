//
//  SearchIndex.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsProperty

/// Links a search entry to the `@Published` property it represents on a
/// settings model, so the drift-guard test can assert every user-facing
/// property has a matching entry.
enum SettingsProperty: Hashable {
    case general(String)
    case advanced(String)
}

// MARK: - SearchEntry

/// One searchable row in the settings search index.
///
/// `titleKey`/`sectionKey` reuse the exact `LocalizedStringKey` literals from
/// the settings panes so no new translation keys are introduced for titles or
/// section headers — they resolve to the same catalog entries the panes use.
/// `titleText`/`sectionText` are the English source strings used for fuzzy
/// matching; locale-aware matching against the runtime localized string is a
/// future enhancement.
///
/// Conforms to `@unchecked Sendable` (not `Hashable`) so the static index
/// arrays are concurrency-safe under Swift 6 strict concurrency.
/// `LocalizedStringKey` is not `Sendable`-annotated in this SDK and not
/// `Hashable`; the entry is immutable (all `let`), so unchecked Sendable
/// conformance is safe — matching the precedent set by `SectionedListItem`.
/// `Identifiable.id` is `String`, which is `Hashable`, so `Identifiable` is
/// satisfied without the whole struct being `Hashable`.
struct SearchEntry: Identifiable, @unchecked Sendable {
    let id: String
    let titleKey: LocalizedStringKey
    let titleText: String
    let descriptionText: String?
    let pane: SettingsNavigationIdentifier
    let sectionKey: LocalizedStringKey?
    let sectionText: String?
    let keywords: [String]
    let property: SettingsProperty?
}

// MARK: - SearchIndex

enum SearchIndex {
    /// Entries indexed on every supported macOS release.
    private static let sharedEntries: [SearchEntry] = paneEntries + generalEntries + advancedEntries
        + displayEntries + hotkeyEntries + layoutEntries

    /// macOS 27-only settings rows, appended when the sidebar search UI is available.
    private static let macOS27Entries: [SearchEntry] = [
        SearchEntry(
            id: "advanced.enableExperimentalSystemItemHiding",
            titleKey: "Hide macOS system items",
            titleText: "Hide macOS system items",
            descriptionText: "Allows items such as Clock, Control Center, and Siri to be moved into hidden sections.",
            pane: .menuBarLayout,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["system items", "clock", "control center", "siri", "hide", "macOS"],
            property: .advanced("enableExperimentalSystemItemHiding")
        ),
        SearchEntry(
            id: "advanced.enableExperimentalOverflowPrevention",
            titleKey: "Prevent native menu bar overflow hiding (experimental)",
            titleText: "Prevent native menu bar overflow hiding (experimental)",
            descriptionText: "On notched displays, macOS may collapse items behind a chevron when the menu bar is full. This writes hidden items' position weights to extreme values so the native overflow collapses them first, keeping visible items on screen.",
            pane: .menuBarLayout,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["overflow", "native", "chevron", "notch", "experimental", "prevent"],
            property: .advanced("enableExperimentalOverflowPrevention")
        ),
    ]

    /// All searchable settings entries, in pane order.
    static var entries: [SearchEntry] {
        if #available(macOS 27, *) {
            return sharedEntries + macOS27Entries
        }
        return sharedEntries
    }

    /// `@Published` property names that are intentionally absent from the
    /// index because they are deprecated, internal, or currently commented out
    /// of the UI. The drift-guard test allows these.
    private static let baseNonSearchableProperties: Set<SettingsProperty> = [
        .general("lastCustomIceIcon"),
        .general("useIceBar"),
        .general("useIceBarOnlyOnNotchedDisplay"),
        .general("iceBarLocation"),
    ]

    /// Advanced settings that only participate in search on macOS 27.
    private static let macOS27AdvancedNonSearchableProperties: Set<SettingsProperty> = [
        .advanced("enableExperimentalWindowHiding"),
        .advanced("enableExperimentalSystemItemHiding"),
        .advanced("enableExperimentalOverflowPrevention"),
    ]

    static var nonSearchableProperties: Set<SettingsProperty> {
        if #available(macOS 27, *) {
            return baseNonSearchableProperties.union([.advanced("enableExperimentalWindowHiding")])
        }
        return baseNonSearchableProperties.union(macOS27AdvancedNonSearchableProperties)
    }

    /// Returns the entries that belong to the given pane.
    static func entries(for pane: SettingsNavigationIdentifier) -> [SearchEntry] {
        entries.filter { $0.pane == pane }
    }

    /// Pure relevance sort: Fuse's `diffScore` is `0` for a perfect match and
    /// increases with worse matches, so the best result has the lowest score.
    /// Delegates to ``SearchRanker/sortedByRelevance(_:)``, the pipe shared
    /// with menu bar item search, so the two surfaces can't drift apart.
    static func sortedByRelevance<T>(_ items: [(item: T, diffScore: Double)]) -> [T] {
        SearchRanker.sortedByRelevance(items)
    }

    // MARK: Pane Rows

    private static let paneEntries: [SearchEntry] = [
        SearchEntry(
            id: "pane.general",
            titleKey: "General",
            titleText: "General",
            descriptionText: nil,
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["general", "launch", "startup", "login", "icon", "rehide"],
            property: nil
        ),
        SearchEntry(
            id: "pane.displays",
            titleKey: "Displays",
            titleText: "Displays",
            descriptionText: nil,
            pane: .displays,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["display", "monitor", "screen", "notch", "spacing", "ice bar", "thaw bar"],
            property: nil
        ),
        SearchEntry(
            id: "pane.menuBarLayout",
            titleKey: "Layout",
            titleText: "Menu Bar Layout",
            descriptionText: nil,
            pane: .menuBarLayout,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["layout", "arrange", "drag", "reorder", "sections", "reset", "overflow", "system items"],
            property: nil
        ),
        SearchEntry(
            id: "pane.menuBarAppearance",
            titleKey: "Appearance",
            titleText: "Menu Bar Appearance",
            descriptionText: nil,
            pane: .menuBarAppearance,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["appearance", "tint", "color", "shadow", "border", "shape", "background", "dark mode"],
            property: nil
        ),
        SearchEntry(
            id: "pane.hotkeys",
            titleKey: "Hotkeys",
            titleText: "Hotkeys",
            descriptionText: nil,
            pane: .hotkeys,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["hotkey", "shortcut", "keyboard", "toggle", "search"],
            property: nil
        ),
        SearchEntry(
            id: "pane.profiles",
            titleKey: "Profiles",
            titleText: "Profiles",
            descriptionText: nil,
            pane: .profiles,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["profile", "preset", "layout", "snapshot"],
            property: nil
        ),
        SearchEntry(
            id: "pane.advanced",
            titleKey: "Advanced",
            titleText: "Advanced",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["advanced", "sections", "search", "tooltips", "diagnostics", "logging", "reset", "context menu"],
            property: nil
        ),
        SearchEntry(
            id: "pane.automation",
            titleKey: "Automation",
            titleText: "Automation",
            descriptionText: nil,
            pane: .automation,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["automation", "url", "scheme", "scripting", "xpc"],
            property: nil
        ),
        SearchEntry(
            id: "pane.about",
            titleKey: "About",
            titleText: "About",
            descriptionText: nil,
            pane: .about,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["about", "version", "update", "credits", "license"],
            property: nil
        ),
    ]

    // MARK: General Settings

    private static let generalEntries: [SearchEntry] = [
        SearchEntry(
            id: "general.launchAtLogin",
            titleKey: "Launch at Login",
            titleText: "Launch at Login",
            descriptionText: nil,
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["launch", "login", "startup", "auto", "start"],
            property: nil
        ),
        SearchEntry(
            id: "general.showIceIcon",
            titleKey: "Show \(Constants.displayName) icon",
            titleText: "Show \(Constants.displayName) icon",
            descriptionText: "Show the \(Constants.displayName) icon in the menu bar. Click to show hidden items, double-click for always-hidden, and right-click for settings.",
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["icon", "show", "menu bar", "status item"],
            property: .general("showIceIcon")
        ),
        SearchEntry(
            id: "general.iceIcon",
            titleKey: "\(Constants.displayName) icon",
            titleText: "\(Constants.displayName) icon",
            descriptionText: "Choose a custom icon to show in the menu bar.",
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["icon", "picker", "custom", "image"],
            property: .general("iceIcon")
        ),
        SearchEntry(
            id: "general.customIceIconIsTemplate",
            titleKey: "Custom icon uses dynamic appearance",
            titleText: "Custom icon uses dynamic appearance",
            descriptionText: "Display the icon as a monochrome image that dynamically adjusts to match the menu bar's appearance.",
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["template", "monochrome", "dark mode", "custom icon"],
            property: .general("customIceIconIsTemplate")
        ),
        SearchEntry(
            id: "general.showOnClick",
            titleKey: "Show on click",
            titleText: "Show on click",
            descriptionText: "Click an empty area of the menu bar to show hidden menu bar items.",
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["click", "show", "hidden"],
            property: .general("showOnClick")
        ),
        SearchEntry(
            id: "general.showOnDoubleClick",
            titleKey: "Double-click for always-hidden",
            titleText: "Double-click for always-hidden",
            descriptionText: "Double-click an empty area of the menu bar to show always-hidden menu bar items.",
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["double click", "always hidden", "show"],
            property: .general("showOnDoubleClick")
        ),
        SearchEntry(
            id: "general.showOnHover",
            titleKey: "Show on hover",
            titleText: "Show on hover",
            descriptionText: "Hover over an empty area of the menu bar to show hidden menu bar items.",
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["hover", "show", "hidden", "mouse"],
            property: .general("showOnHover")
        ),
        SearchEntry(
            id: "general.showOnScroll",
            titleKey: "Show on scroll",
            titleText: "Show on scroll",
            descriptionText: "Scroll or swipe in the menu bar to show hidden menu bar items.",
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["scroll", "swipe", "show", "hidden", "gesture"],
            property: .general("showOnScroll")
        ),
        SearchEntry(
            id: "general.autoRehide",
            titleKey: "Automatically rehide",
            titleText: "Automatically rehide",
            descriptionText: nil,
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["rehide", "auto", "automatic", "hide"],
            property: .general("autoRehide")
        ),
        SearchEntry(
            id: "general.rehideStrategy",
            titleKey: "Strategy",
            titleText: "Rehide strategy",
            descriptionText: nil,
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["rehide", "strategy", "smart", "timed", "focused app"],
            property: .general("rehideStrategy")
        ),
        SearchEntry(
            id: "general.rehideInterval",
            titleKey: "Rehide interval",
            titleText: "Rehide interval",
            descriptionText: "Menu bar items are rehidden after a fixed amount of time.",
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["rehide", "interval", "timed", "seconds", "delay"],
            property: .general("rehideInterval")
        ),
        SearchEntry(
            id: "general.tempShowInterval",
            titleKey: "Temporarily shown item delay",
            titleText: "Temporarily shown item delay",
            descriptionText: "The amount of time to wait before hiding temporarily shown menu bar items.",
            pane: .general,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["temp", "temporary", "show", "delay", "seconds"],
            property: .general("tempShowInterval")
        ),
        SearchEntry(
            id: "general.iceBarLocationOnHotkey",
            titleKey: "Show at mouse pointer on hotkey",
            titleText: "Show at mouse pointer on hotkey",
            descriptionText: "Always show the \(Constants.displayName) Bar at the mouse pointer's location when it is shown using a hotkey.",
            pane: .advanced,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["ice bar", "thaw bar", "mouse", "pointer", "hotkey", "location"],
            property: .general("iceBarLocationOnHotkey")
        ),
    ]

    // MARK: Advanced Settings

    private static let advancedEntries: [SearchEntry] = [
        SearchEntry(
            id: "advanced.enableAlwaysHiddenSection",
            titleKey: "Enable the always-hidden section",
            titleText: "Enable the always-hidden section",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Menu Bar Sections",
            sectionText: "Menu Bar Sections",
            keywords: ["always hidden", "section", "enable"],
            property: .advanced("enableAlwaysHiddenSection")
        ),
        SearchEntry(
            id: "advanced.useOptionClickToShowAlwaysHiddenSection",
            titleKey: "Use Option-click to open always-hidden section",
            titleText: "Use Option-click to open always-hidden section",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Menu Bar Sections",
            sectionText: "Menu Bar Sections",
            keywords: ["option", "click", "always hidden", "alt"],
            property: .advanced("useOptionClickToShowAlwaysHiddenSection")
        ),
        SearchEntry(
            id: "advanced.useDoubleClickToShowAlwaysHiddenSection",
            titleKey: "Double-click \(Constants.displayName) icon to open always-hidden section",
            titleText: "Double-click \(Constants.displayName) icon to open always-hidden section",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Menu Bar Sections",
            sectionText: "Menu Bar Sections",
            keywords: ["double click", "always hidden", "icon"],
            property: .advanced("useDoubleClickToShowAlwaysHiddenSection")
        ),
        SearchEntry(
            id: "advanced.showAllSectionsOnUserDrag",
            titleKey: "Show all sections when ⌘ Command + dragging menu bar items",
            titleText: "Show all sections when Command + dragging menu bar items",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Menu Bar Sections",
            sectionText: "Menu Bar Sections",
            keywords: ["drag", "command", "sections", "show all"],
            property: .advanced("showAllSectionsOnUserDrag")
        ),
        SearchEntry(
            id: "advanced.sectionDividerStyle",
            titleKey: "Section divider style",
            titleText: "Section divider style",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Menu Bar Sections",
            sectionText: "Menu Bar Sections",
            keywords: ["divider", "style", "chevron", "separator", "section"],
            property: .advanced("sectionDividerStyle")
        ),
        SearchEntry(
            id: "advanced.searchSectionOrder",
            titleKey: "Search section ordering",
            titleText: "Search section ordering",
            descriptionText: "Choose which menu bar sections appear in the search panel, and in what order.",
            pane: .advanced,
            sectionKey: "Search",
            sectionText: "Search",
            keywords: ["search", "section", "order", "panel", "reorder"],
            property: .advanced("searchSectionOrder")
        ),
        SearchEntry(
            id: "advanced.searchIncludeVisible",
            titleKey: "Include visible section in search",
            titleText: "Include visible section in search",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Search",
            sectionText: "Search",
            keywords: ["search", "visible", "include", "section"],
            property: .advanced("searchIncludeVisible")
        ),
        SearchEntry(
            id: "advanced.searchIncludeHidden",
            titleKey: "Include hidden section in search",
            titleText: "Include hidden section in search",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Search",
            sectionText: "Search",
            keywords: ["search", "hidden", "include", "section"],
            property: .advanced("searchIncludeHidden")
        ),
        SearchEntry(
            id: "advanced.searchIncludeAlwaysHidden",
            titleKey: "Include always-hidden section in search",
            titleText: "Include always-hidden section in search",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Search",
            sectionText: "Search",
            keywords: ["search", "always hidden", "include", "section"],
            property: .advanced("searchIncludeAlwaysHidden")
        ),
        SearchEntry(
            id: "advanced.showMenuBarTooltips",
            titleKey: "Show tooltips in the menu bar",
            titleText: "Show tooltips in the menu bar",
            descriptionText: "Show a tooltip when hovering over menu bar items in the actual menu bar.",
            pane: .advanced,
            sectionKey: "Tooltips",
            sectionText: "Tooltips",
            keywords: ["tooltip", "hover", "menu bar"],
            property: .advanced("showMenuBarTooltips")
        ),
        SearchEntry(
            id: "advanced.tooltipDelay",
            titleKey: "Tooltip delay",
            titleText: "Tooltip delay",
            descriptionText: "The amount of time to wait before showing a tooltip over a menu bar item.",
            pane: .advanced,
            sectionKey: "Tooltips",
            sectionText: "Tooltips",
            keywords: ["tooltip", "delay", "hover", "seconds"],
            property: .advanced("tooltipDelay")
        ),
        SearchEntry(
            id: "advanced.enableMenuBarItemOverflow",
            titleKey: "Enable menu bar item overflow",
            titleText: "Enable menu bar item overflow",
            descriptionText: "Move menu bar items from the visible section into the hidden section when they don't fit beside the notch on a notched display.",
            pane: .advanced,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["overflow", "notch", "fit", "visible", "hidden"],
            property: .advanced("enableMenuBarItemOverflow")
        ),
        SearchEntry(
            id: "advanced.useLCSSortingOnNotchedDisplays",
            titleKey: "Use LCS sorting on notched displays",
            titleText: "Use LCS sorting on notched displays",
            descriptionText: "Use the faster LCS algorithm for profile sorting on notched displays instead of the full sort.",
            pane: .advanced,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["lcs", "sorting", "notch", "profile", "sort"],
            property: .advanced("useLCSSortingOnNotchedDisplays")
        ),
        SearchEntry(
            id: "advanced.hideApplicationMenus",
            titleKey: "Hide app menus when showing menu bar items",
            titleText: "Hide app menus when showing menu bar items",
            descriptionText: "Make more room in the menu bar by hiding the current app menus if needed.",
            pane: .advanced,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["app menus", "hide", "application", "menu bar"],
            property: .advanced("hideApplicationMenus")
        ),
        SearchEntry(
            id: "advanced.enableSecondaryContextMenu",
            titleKey: "Enable secondary context menu",
            titleText: "Enable secondary context menu",
            descriptionText: "Right-click in an empty area of the menu bar to display a minimal version of \(Constants.displayName)'s menu.",
            pane: .advanced,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["context menu", "right click", "secondary"],
            property: .advanced("enableSecondaryContextMenu")
        ),
        SearchEntry(
            id: "advanced.enableSecondaryContextMenuQuit",
            titleKey: "Enable secondary context menu quit",
            titleText: "Enable secondary context menu quit",
            descriptionText: "Add a Quit \(Constants.displayName) item to the bottom of the secondary context menu.",
            pane: .advanced,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["context menu", "quit", "secondary"],
            property: .advanced("enableSecondaryContextMenuQuit")
        ),
        SearchEntry(
            id: "advanced.showOnHoverDelay",
            titleKey: "Show on hover delay",
            titleText: "Show on hover delay",
            descriptionText: "The amount of time to wait before showing on hover.",
            pane: .advanced,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["hover", "delay", "show", "seconds"],
            property: .advanced("showOnHoverDelay")
        ),
        SearchEntry(
            id: "advanced.iconRefreshInterval",
            titleKey: "Icon refresh rate",
            titleText: "Icon refresh rate",
            descriptionText: "How often animated menu bar icons are refreshed in panels. Higher values are smoother but use more CPU.",
            pane: .advanced,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["icon", "refresh", "rate", "fps", "animated", "cpu"],
            property: .advanced("iconRefreshInterval")
        ),
        SearchEntry(
            id: "advanced.enableDiagnosticLogging",
            titleKey: "Enable diagnostic logging",
            titleText: "Enable diagnostic logging",
            descriptionText: "Writes detailed debug logs to a file for troubleshooting. Log files are saved to ~/Library/Logs/Thaw/.",
            pane: .advanced,
            sectionKey: "Diagnostics",
            sectionText: "Diagnostics",
            keywords: ["diagnostic", "logging", "debug", "logs", "troubleshoot"],
            property: .advanced("enableDiagnosticLogging")
        ),
    ]

    // MARK: Display Settings

    /// Display settings are configuration-based (per-display and global
    /// templates on `DisplaySettingsManager`), not direct `@Published` toggles,
    /// so they are not covered by the drift guard. They are indexed for search
    /// discoverability.
    private static let displayEntries: [SearchEntry] = [
        SearchEntry(
            id: "displays.useIceBar",
            titleKey: "Use \(Constants.displayName) Bar",
            titleText: "Use \(Constants.displayName) Bar",
            descriptionText: "Show hidden menu bar items in a separate bar below the menu bar.",
            pane: .displays,
            sectionKey: "Global",
            sectionText: "Global",
            keywords: ["ice bar", "thaw bar", "hidden", "separate bar"],
            property: nil
        ),
        SearchEntry(
            id: "displays.alwaysShowHiddenItems",
            titleKey: "Always show hidden items",
            titleText: "Always show hidden items",
            descriptionText: "Always show hidden menu bar items in the menu bar.",
            pane: .displays,
            sectionKey: "Global",
            sectionText: "Global",
            keywords: ["always", "show", "hidden", "visible"],
            property: nil
        ),
        SearchEntry(
            id: "displays.iceBarLocation",
            titleKey: "Location",
            titleText: "\(Constants.displayName) Bar location",
            descriptionText: "The \(Constants.displayName) Bar's location changes based on context.",
            pane: .displays,
            sectionKey: "Global",
            sectionText: "Global",
            keywords: ["ice bar", "thaw bar", "location", "mouse", "aligned"],
            property: nil
        ),
        SearchEntry(
            id: "displays.iceBarLayout",
            titleKey: "Layout",
            titleText: "\(Constants.displayName) Bar layout",
            descriptionText: "Items are arranged in a single horizontal row, stacked vertically, or in a grid.",
            pane: .displays,
            sectionKey: "Global",
            sectionText: "Global",
            keywords: ["ice bar", "thaw bar", "layout", "horizontal", "vertical", "grid", "columns"],
            property: nil
        ),
        SearchEntry(
            id: "displays.itemSpacing",
            titleKey: "Menu bar item spacing",
            titleText: "Menu bar item spacing",
            descriptionText: "Apply briefly relaunches apps with menu bar items so they pick up the new spacing.",
            pane: .displays,
            sectionKey: "Global",
            sectionText: "Global",
            keywords: ["spacing", "padding", "menu bar", "items", "gap"],
            property: nil
        ),
        SearchEntry(
            id: "displays.confirmSpacingRelaunch",
            titleKey: "Confirm before relaunching apps",
            titleText: "Confirm before relaunching apps",
            descriptionText: "Before a display change or spacing edit relaunches your menu bar apps, \(Constants.displayName) asks you to confirm.",
            pane: .displays,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["confirm", "relaunch", "apps", "spacing", "restart"],
            property: nil
        ),
    ]

    // MARK: Hotkey Settings

    /// Hotkey bindings are dictionary-based on `HotkeysSettings`, not simple
    /// `@Published` toggles, so they are not covered by the drift guard.
    private static let hotkeyEntries: [SearchEntry] = [
        SearchEntry(
            id: "hotkeys.toggleHiddenSection",
            titleKey: "Toggle the hidden section",
            titleText: "Toggle the hidden section",
            descriptionText: nil,
            pane: .hotkeys,
            sectionKey: "Menu Bar Sections",
            sectionText: "Menu Bar Sections",
            keywords: ["toggle", "hidden", "section", "hotkey", "shortcut"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.toggleAlwaysHiddenSection",
            titleKey: "Toggle the always-hidden section",
            titleText: "Toggle the always-hidden section",
            descriptionText: nil,
            pane: .hotkeys,
            sectionKey: "Menu Bar Sections",
            sectionText: "Menu Bar Sections",
            keywords: ["toggle", "always hidden", "section", "hotkey", "shortcut"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.searchMenuBarItems",
            titleKey: "Search menu bar items",
            titleText: "Search menu bar items",
            descriptionText: nil,
            pane: .hotkeys,
            sectionKey: "Menu Bar Items",
            sectionText: "Menu Bar Items",
            keywords: ["search", "menu bar items", "hotkey", "shortcut", "panel"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.openMenuBarItems",
            titleKey: "Open menu bar items",
            titleText: "Open menu bar items",
            descriptionText: nil,
            pane: .hotkeys,
            sectionKey: "Menu Bar Items",
            sectionText: "Menu Bar Items",
            keywords: ["open", "menu bar items", "hotkey", "per item"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.enableIceBar",
            titleKey: "Enable the \(Constants.displayName) Bar",
            titleText: "Enable the \(Constants.displayName) Bar",
            descriptionText: nil,
            pane: .hotkeys,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["enable", "ice bar", "thaw bar", "hotkey", "shortcut"],
            property: nil
        ),
        SearchEntry(
            id: "hotkeys.toggleApplicationMenus",
            titleKey: "Toggle application menus",
            titleText: "Toggle application menus",
            descriptionText: nil,
            pane: .hotkeys,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["toggle", "application menus", "app menus", "hotkey", "shortcut"],
            property: nil
        ),
    ]

    // MARK: Layout Settings

    private static let layoutEntries: [SearchEntry] = [
        SearchEntry(
            id: "layout.resetMenuBarLayout",
            titleKey: "Reset menu bar layout",
            titleText: "Reset menu bar layout",
            descriptionText: "Moves every movable item except the \(Constants.displayName) icon to the selected section — just like a fresh install.",
            pane: .menuBarLayout,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["reset", "layout", "fresh", "visible", "hidden", "arrange"],
            property: nil
        ),
    ]
}
