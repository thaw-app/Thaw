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
nonisolated enum SettingsProperty: Hashable {
    case general(String)
    case advanced(String)
}

// MARK: - SearchEntry

/// One searchable row in the settings search index.
///
/// `titleKey`/`sectionKey` reuse the exact `LocalizedStringKey` literals from
/// the settings panes so no new translation keys are introduced for titles or
/// section headers — they resolve to the same catalog entries the panes use.
/// `titleText`/`sectionText`/`descriptionText` are the English source strings,
/// which are also the catalog keys, so ``localizedTitle(bundle:)`` and its
/// siblings resolve them to the running localization for fuzzy matching. `keywords`
/// stays English: it is a search-only alias list with no catalog entries, and
/// the English title is indexed alongside the translated one so terms users
/// saw in docs or release notes keep matching in a localized build.
///
/// Conforms to `@unchecked Sendable` (not `Hashable`) so the static index
/// arrays are concurrency-safe under Swift 6 strict concurrency.
/// `LocalizedStringKey` is not `Sendable`-annotated in this SDK and not
/// `Hashable`; the entry is immutable (all `let`), so unchecked Sendable
/// conformance is safe — matching the precedent set by `SectionedListItem`.
/// `Identifiable.id` is `String`, which is `Hashable`, so `Identifiable` is
/// satisfied without the whole struct being `Hashable`.
nonisolated struct SearchEntry: Identifiable, @unchecked Sendable {
    let id: String
    let titleKey: LocalizedStringKey
    let titleText: String
    let descriptionText: String?
    let pane: SettingsNavigationIdentifier
    let sectionKey: LocalizedStringKey?
    let sectionText: String?
    let keywords: [String]
    let property: SettingsProperty?

    /// The title as the settings pane renders it.
    ///
    /// The English source doubles as the catalog key, so this resolves the
    /// same entry the pane's `titleKey` does.
    ///
    /// - Parameter bundle: The bundle to resolve against. Defaults to
    ///   `.main`, which picks the running localization; tests pass a
    ///   specific `.lproj` bundle, since the `locale:` argument of
    ///   `String(localized:)` only selects formatting, not which
    ///   localization is looked up.
    func localizedTitle(bundle: Bundle = .main) -> String {
        String(localized: String.LocalizationValue(titleText), bundle: bundle)
    }

    /// The section header as rendered, when the entry has one.
    func localizedSection(bundle: Bundle = .main) -> String? {
        sectionText.map { String(localized: String.LocalizationValue($0), bundle: bundle) }
    }

    /// The annotation text as rendered, when the entry has one.
    func localizedDescription(bundle: Bundle = .main) -> String? {
        descriptionText.map { String(localized: String.LocalizationValue($0), bundle: bundle) }
    }

    var disclosure: AppNavigationState.SettingsDisclosure? {
        switch id {
        case "advanced.alwaysUseAppIconForMenuBarItems",
             "advanced.automaticArrangementEnabled",
             "advanced.enableMenuBarItemOverflow",
             "advanced.useThawBarOnNotchOverflow",
             "advanced.menuBarOrderFulfillmentTimeout":
            .advancedLayoutControls
        default:
            nil
        }
    }
}

// MARK: - SearchIndex

nonisolated enum SearchIndex {
    /// Entries indexed on every supported macOS release.
    private static let sharedEntries: [SearchEntry] = paneEntries + generalEntries + revealEntries + advancedEntries
        + displayEntries + hotkeyEntries + layoutEntries + appearanceEntries

    /// macOS 27-only settings rows, appended when the sidebar search UI is
    /// available. Currently empty: rows are only added here once a matching
    /// control is actually exposed in a settings pane.
    private static let macOS27Entries: [SearchEntry] = []

    /// All searchable settings entries, in pane order.
    ///
    /// The set is static for a given OS, so it is resolved once and cached
    /// rather than re-concatenated on every access (the search path reads it
    /// per keystroke).
    static let entries: [SearchEntry] = {
        if #available(macOS 27, *) {
            return sharedEntries + macOS27Entries
        }
        return sharedEntries
    }()

    /// `@Published` property names that are intentionally absent from the
    /// index because they are deprecated, internal, or currently commented out
    /// of the UI. The drift-guard test allows these.
    private static let baseNonSearchableProperties: Set<SettingsProperty> = [
        .general("lastCustomIceIcon"),
        .general("useIceBar"),
        .general("useIceBarOnlyOnNotchedDisplay"),
        .general("iceBarLocation"),
        // URI/Defaults-only experimental toggle with no Settings UI; excluded
        // on every OS version rather than only on macOS <27.
        .advanced("enableExperimentalOverflowPrevention"),
    ]

    /// Advanced settings that only participate in search on macOS 27.
    private static let macOS27AdvancedNonSearchableProperties: Set<SettingsProperty> = [
        .advanced("alwaysUseAppIconForMenuBarItems"),
        .advanced("enableExperimentalWindowHiding"),
        .advanced("enableExperimentalSystemItemHiding"),
        .advanced("menuBarOrderFulfillmentTimeout"),
    ]

    static var nonSearchableProperties: Set<SettingsProperty> {
        if #available(macOS 27, *) {
            return baseNonSearchableProperties.union([.advanced("enableExperimentalWindowHiding")])
        }
        return baseNonSearchableProperties.union(macOS27AdvancedNonSearchableProperties)
    }

    /// ``entries`` bucketed by pane, resolved once for the same reason
    /// ``entries`` itself is: the search path reads it per keystroke, and a
    /// filter per lookup rescans the whole index for each pane.
    private static let entriesByPane: [SettingsNavigationIdentifier: [SearchEntry]] =
        Dictionary(grouping: entries, by: \.pane)

    /// Returns the entries that belong to the given pane.
    static func entries(for pane: SettingsNavigationIdentifier) -> [SearchEntry] {
        entriesByPane[pane] ?? []
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
            keywords: ["general", "launch", "startup", "login", "icon", "reveal", "show", "hide", "hover", "click", "scroll", "rehide", "gesture"],
            property: nil
        ),
        SearchEntry(
            id: "pane.menuBarLayout",
            titleKey: "Layout",
            titleText: "Layout",
            descriptionText: nil,
            pane: .menuBarLayout,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["layout", "arrange", "drag", "reorder", "sections", "reset", "overflow", "system items", "always hidden", "divider"],
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
            keywords: ["display", "monitor", "screen", "notch", "spacing", "ice bar", "thaw bar", "arrangement"],
            property: nil
        ),
        SearchEntry(
            id: "pane.menuBarAppearance",
            titleKey: "Appearance",
            titleText: "Appearance",
            descriptionText: nil,
            pane: .menuBarAppearance,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["appearance", "tint", "color", "shadow", "border", "shape", "background", "dark mode", "fill", "glass"],
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
            keywords: ["advanced", "search", "tooltips", "reset", "context menu"],
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
            id: "pane.triggers",
            titleKey: "Triggers",
            titleText: "Triggers",
            descriptionText: "Automatically move menu bar items when system conditions change.",
            pane: .triggers,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["triggers", "conditions", "automation", "battery", "focus", "network", "reveal", "hide"],
            property: nil
        ),
        SearchEntry(
            id: "pane.developer",
            titleKey: "Dev Mode Flags",
            titleText: "Dev Mode Flags",
            descriptionText: "Enable and inspect experimental trigger sources.",
            pane: .developer,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["developer", "dev mode", "flags", "experimental", "trigger sources", "diagnostics"],
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
            id: "general.iceBarLocationOnHotkey",
            titleKey: "Show at mouse pointer on hotkey",
            titleText: "Show at mouse pointer on hotkey",
            descriptionText: "Always show the \(Constants.displayName) Bar at the mouse pointer's location when it is shown using a hotkey.",
            pane: .displays,
            sectionKey: "Global",
            sectionText: "Global",
            keywords: ["ice bar", "thaw bar", "mouse", "pointer", "hotkey", "location"],
            property: .general("iceBarLocationOnHotkey")
        ),
    ]

    // MARK: Reveal Settings

    private static let revealEntries: [SearchEntry] = [
        SearchEntry(
            id: "general.showOnClick",
            titleKey: "Show on click",
            titleText: "Show on click",
            descriptionText: "Click an empty area of the menu bar to show hidden menu bar items.",
            pane: .general,
            sectionKey: "Empty menu bar area",
            sectionText: "Empty menu bar area",
            keywords: ["click", "show", "hidden"],
            property: .general("showOnClick")
        ),
        SearchEntry(
            id: "general.showOnDoubleClick",
            titleKey: "Double-click for always-hidden",
            titleText: "Double-click for always-hidden",
            descriptionText: "Double-click an empty area of the menu bar to show always-hidden menu bar items.",
            pane: .general,
            sectionKey: "Empty menu bar area",
            sectionText: "Empty menu bar area",
            keywords: ["double click", "always hidden", "show"],
            property: .general("showOnDoubleClick")
        ),
        SearchEntry(
            id: "general.showOnHover",
            titleKey: "Show on hover",
            titleText: "Show on hover",
            descriptionText: "Hover over an empty area of the menu bar to show hidden menu bar items.",
            pane: .general,
            sectionKey: "Empty menu bar area",
            sectionText: "Empty menu bar area",
            keywords: ["hover", "show", "hidden", "mouse"],
            property: .general("showOnHover")
        ),
        SearchEntry(
            id: "general.showOnScroll",
            titleKey: "Show on scroll",
            titleText: "Show on scroll",
            descriptionText: "Scroll or swipe in the menu bar to show hidden menu bar items.",
            pane: .general,
            sectionKey: "Empty menu bar area",
            sectionText: "Empty menu bar area",
            keywords: ["scroll", "swipe", "show", "hidden", "gesture"],
            property: .general("showOnScroll")
        ),
        SearchEntry(
            id: "general.autoRehide",
            titleKey: "Automatically rehide",
            titleText: "Automatically rehide",
            descriptionText: nil,
            pane: .general,
            sectionKey: "After revealing",
            sectionText: "After revealing",
            keywords: ["rehide", "auto", "automatic", "hide"],
            property: .general("autoRehide")
        ),
        SearchEntry(
            id: "general.rehideStrategy",
            titleKey: "Strategy",
            titleText: "Rehide strategy",
            descriptionText: nil,
            pane: .general,
            sectionKey: "After revealing",
            sectionText: "After revealing",
            keywords: ["rehide", "strategy", "smart", "timed", "focused app"],
            property: .general("rehideStrategy")
        ),
        SearchEntry(
            id: "general.rehideInterval",
            titleKey: "Rehide interval",
            titleText: "Rehide interval",
            descriptionText: "Menu bar items are rehidden after a fixed amount of time.",
            pane: .general,
            sectionKey: "After revealing",
            sectionText: "After revealing",
            keywords: ["rehide", "interval", "timed", "seconds", "delay"],
            property: .general("rehideInterval")
        ),
        SearchEntry(
            id: "advanced.useOptionClickToShowAlwaysHiddenSection",
            titleKey: "Use Option-click to open always-hidden section",
            titleText: "Use Option-click to open always-hidden section",
            descriptionText: nil,
            pane: .general,
            sectionKey: "\(Constants.displayName) icon",
            sectionText: "\(Constants.displayName) icon",
            keywords: ["option", "click", "always hidden", "alt"],
            property: .advanced("useOptionClickToShowAlwaysHiddenSection")
        ),
        SearchEntry(
            id: "advanced.useDoubleClickToShowAlwaysHiddenSection",
            titleKey: "Double-click \(Constants.displayName) icon to open always-hidden section",
            titleText: "Double-click \(Constants.displayName) icon to open always-hidden section",
            descriptionText: nil,
            pane: .general,
            sectionKey: "\(Constants.displayName) icon",
            sectionText: "\(Constants.displayName) icon",
            keywords: ["double click", "always hidden", "icon"],
            property: .advanced("useDoubleClickToShowAlwaysHiddenSection")
        ),
        SearchEntry(
            id: "advanced.showAllSectionsOnUserDrag",
            titleKey: "Show all sections when ⌘ Command + dragging menu bar items",
            titleText: "Show all sections when Command + dragging menu bar items",
            descriptionText: nil,
            pane: .general,
            sectionKey: "While rearranging",
            sectionText: "While rearranging",
            keywords: ["drag", "command", "sections", "show all"],
            property: .advanced("showAllSectionsOnUserDrag")
        ),
        SearchEntry(
            id: "advanced.showOnHoverDelay",
            titleKey: "Show on hover delay",
            titleText: "Show on hover delay",
            descriptionText: "The amount of time to wait before showing on hover.",
            pane: .general,
            sectionKey: "Empty menu bar area",
            sectionText: "Empty menu bar area",
            keywords: ["hover", "delay", "show", "seconds"],
            property: .advanced("showOnHoverDelay")
        ),
    ]

    // MARK: Advanced Settings

    private static let advancedEntries: [SearchEntry] = [
        SearchEntry(
            id: "advanced.searchSectionOrder",
            titleKey: "Search section ordering",
            titleText: "Search section ordering",
            descriptionText: "Choose which menu bar sections appear in the search panel, and in what order.",
            pane: .advanced,
            sectionKey: "Menu Bar Search",
            sectionText: "Menu Bar Search",
            keywords: ["search", "section", "order", "panel", "reorder"],
            property: .advanced("searchSectionOrder")
        ),
        SearchEntry(
            id: "advanced.searchIncludeVisible",
            titleKey: "Include visible section in search",
            titleText: "Include visible section in search",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Menu Bar Search",
            sectionText: "Menu Bar Search",
            keywords: ["search", "visible", "include", "section"],
            property: .advanced("searchIncludeVisible")
        ),
        SearchEntry(
            id: "advanced.searchIncludeHidden",
            titleKey: "Include hidden section in search",
            titleText: "Include hidden section in search",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Menu Bar Search",
            sectionText: "Menu Bar Search",
            keywords: ["search", "hidden", "include", "section"],
            property: .advanced("searchIncludeHidden")
        ),
        SearchEntry(
            id: "advanced.searchIncludeAlwaysHidden",
            titleKey: "Include always-hidden section in search",
            titleText: "Include always-hidden section in search",
            descriptionText: nil,
            pane: .advanced,
            sectionKey: "Menu Bar Search",
            sectionText: "Menu Bar Search",
            keywords: ["search", "always hidden", "include", "section"],
            property: .advanced("searchIncludeAlwaysHidden")
        ),
        SearchEntry(
            id: "advanced.moveCursorToRevealedItem",
            titleKey: "Move the pointer to revealed items",
            titleText: "Move the pointer to revealed items",
            descriptionText: """
            When you open a menu bar item from the search panel, move the mouse \
            pointer next to it, so its menu appears under the pointer.
            """,
            pane: .advanced,
            sectionKey: "Menu Bar Search",
            sectionText: "Menu Bar Search",
            keywords: ["search", "cursor", "pointer", "mouse", "move"],
            property: .advanced("moveCursorToRevealedItem")
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
            id: "advanced.automaticArrangementEnabled",
            // Reuses catalog strings that are already fully translated, so
            // the entry ships localized without a new Crowdin round.
            titleKey: "Arrange menu bar items.",
            titleText: "Arrange menu bar items.",
            descriptionText: "Items can also be arranged by ⌘ Command + dragging them in the menu bar.",
            pane: .menuBarLayout,
            sectionKey: "Advanced layout controls",
            sectionText: "Advanced layout controls",
            keywords: ["arrange", "automatic", "manual", "reorder", "layout"],
            property: .advanced("automaticArrangementEnabled")
        ),
        SearchEntry(
            id: "advanced.enableMenuBarItemOverflow",
            titleKey: "Move items that don't fit into Hidden",
            titleText: "Move items that don't fit into Hidden",
            descriptionText: "Move menu bar items from the visible section into the hidden section when they don't fit beside the notch on a notched display.",
            pane: .menuBarLayout,
            sectionKey: "Advanced layout controls",
            sectionText: "Advanced layout controls",
            keywords: ["overflow", "notch", "fit", "visible", "hidden"],
            property: .advanced("enableMenuBarItemOverflow")
        ),
        SearchEntry(
            id: "advanced.useThawBarOnNotchOverflow",
            titleKey: "Use the Thaw Bar while items are overflowed",
            titleText: "Use the Thaw Bar while items are overflowed",
            descriptionText: "Reveal hidden items through the Thaw Bar while notch overflow has items ejected, since the visible row has no room left to expand into.",
            pane: .menuBarLayout,
            sectionKey: "Advanced layout controls",
            sectionText: "Advanced layout controls",
            keywords: ["overflow", "notch", "thaw bar", "ice bar", "hidden", "reveal"],
            property: .advanced("useThawBarOnNotchOverflow")
        ),
        SearchEntry(
            id: "advanced.hideApplicationMenus",
            titleKey: "Hide app menus when showing menu bar items",
            titleText: "Hide app menus when showing menu bar items",
            descriptionText: "Make more room in the menu bar by hiding the current app menus if needed.",
            pane: .advanced,
            sectionKey: "Menu bar behavior",
            sectionText: "Menu bar behavior",
            keywords: ["app menus", "hide", "application", "menu bar"],
            property: .advanced("hideApplicationMenus")
        ),
        SearchEntry(
            id: "advanced.enableSecondaryContextMenu",
            titleKey: "Enable secondary context menu",
            titleText: "Enable secondary context menu",
            descriptionText: "Right-click in an empty area of the menu bar to display a minimal version of \(Constants.displayName)'s menu.",
            pane: .advanced,
            sectionKey: "Menu bar behavior",
            sectionText: "Menu bar behavior",
            keywords: ["context menu", "right click", "secondary"],
            property: .advanced("enableSecondaryContextMenu")
        ),
        SearchEntry(
            id: "advanced.enableSecondaryContextMenuQuit",
            titleKey: "Enable secondary context menu quit",
            titleText: "Enable secondary context menu quit",
            descriptionText: "Add a Quit \(Constants.displayName) item to the bottom of the secondary context menu.",
            pane: .advanced,
            sectionKey: "Menu bar behavior",
            sectionText: "Menu bar behavior",
            keywords: ["context menu", "quit", "secondary"],
            property: .advanced("enableSecondaryContextMenuQuit")
        ),
        SearchEntry(
            id: "advanced.iconRefreshInterval",
            titleKey: "Icon refresh rate",
            titleText: "Icon refresh rate",
            descriptionText: "Controls how often menu bar icon previews refresh while a panel is open.",
            pane: .menuBarLayout,
            sectionKey: "Icon previews",
            sectionText: "Icon previews",
            keywords: ["icon", "refresh", "rate", "fps", "animated", "cpu"],
            property: .advanced("iconRefreshInterval")
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
            id: "displays.useThawBarForAlwaysHidden",
            titleKey: "Always-hidden items only",
            titleText: "Always-hidden items only",
            descriptionText: "Show always-hidden menu bar items in the \(Constants.displayName) Bar, while hidden items keep expanding in the menu bar.",
            pane: .displays,
            sectionKey: "Global",
            sectionText: "Global",
            keywords: ["ice bar", "thaw bar", "always-hidden", "always hidden", "only"],
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
            titleKey: "Arrangement",
            titleText: "\(Constants.displayName) Bar arrangement",
            descriptionText: "Items are arranged in a single horizontal row, stacked vertically, or in a grid.",
            pane: .displays,
            sectionKey: "Global",
            sectionText: "Global",
            keywords: ["ice bar", "thaw bar", "layout", "arrangement", "horizontal", "vertical", "grid", "columns"],
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
        SearchEntry(
            id: "hotkeys.toggleAutoRehide",
            titleKey: "Toggle automatic rehiding",
            titleText: "Toggle automatic rehiding",
            descriptionText: nil,
            pane: .hotkeys,
            sectionKey: "Other",
            sectionText: "Other",
            keywords: ["toggle", "auto rehide", "automatically rehide", "hotkey", "shortcut"],
            property: nil
        ),
    ]

    // MARK: Layout Settings

    private static let layoutEntries: [SearchEntry] = [
        SearchEntry(
            id: "advanced.enableAlwaysHiddenSection",
            titleKey: "Enable the always-hidden section",
            titleText: "Enable the always-hidden section",
            descriptionText: nil,
            pane: .menuBarLayout,
            sectionKey: "Sections",
            sectionText: "Sections",
            keywords: ["always hidden", "section", "enable"],
            property: .advanced("enableAlwaysHiddenSection")
        ),
        SearchEntry(
            id: "advanced.sectionDividerStyle",
            titleKey: "Section divider style",
            titleText: "Section divider style",
            descriptionText: nil,
            pane: .menuBarLayout,
            sectionKey: "Sections",
            sectionText: "Sections",
            keywords: ["divider", "style", "chevron", "separator", "section"],
            property: .advanced("sectionDividerStyle")
        ),
        SearchEntry(
            id: "layout.spacers",
            titleKey: "Spacers",
            titleText: "Spacers",
            descriptionText: "Insert empty gap items into the menu bar and adjust their width.",
            pane: .menuBarLayout,
            sectionKey: "Spacers",
            sectionText: "Spacers",
            keywords: ["spacer", "gap", "space", "separator", "width"],
            property: nil
        ),
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

    // MARK: Appearance Settings

    private static let appearanceEntries: [SearchEntry] = [
        SearchEntry(
            id: "appearance.isDynamic",
            titleKey: "Use different settings for Light and Dark Mode",
            titleText: "Use different settings for Light and Dark Mode",
            descriptionText: "Edit Light and Dark separately. Switch modes below to customize each.",
            pane: .menuBarAppearance,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["dynamic", "light", "dark", "appearance", "mode"],
            property: nil
        ),
        SearchEntry(
            id: "appearance.background",
            titleKey: "Background",
            titleText: "Background",
            descriptionText: "Fills the menu bar behind or around a custom shape.",
            pane: .menuBarAppearance,
            sectionKey: "Background",
            sectionText: "Background",
            keywords: ["background", "style", "solid", "gradient", "glass", "adaptive", "opacity", "shadow", "border"],
            property: nil
        ),
        SearchEntry(
            id: "appearance.shape",
            titleKey: "Shape",
            titleText: "Shape",
            descriptionText: nil,
            pane: .menuBarAppearance,
            sectionKey: "Shape",
            sectionText: "Shape",
            keywords: ["shape", "full", "split", "notch", "end cap", "margin", "inset"],
            property: nil
        ),
        SearchEntry(
            id: "appearance.isInset",
            titleKey: "Inset on notched displays",
            titleText: "Inset on notched displays",
            descriptionText: "Shrinks the shape slightly so it sits below the notch.",
            pane: .menuBarAppearance,
            sectionKey: "Shape",
            sectionText: "Shape",
            keywords: ["inset", "notch", "shape"],
            property: nil
        ),
        SearchEntry(
            id: "appearance.shapeFill",
            titleKey: "Shape fill",
            titleText: "Shape fill",
            descriptionText: "Colors the area inside the shape.",
            pane: .menuBarAppearance,
            sectionKey: "Shape fill",
            sectionText: "Shape fill",
            keywords: ["tint", "fill", "style", "solid", "gradient", "glass", "adaptive", "opacity", "shadow", "border"],
            property: nil
        ),
        SearchEntry(
            id: "appearance.reset",
            titleKey: "Reset Appearance",
            titleText: "Reset Appearance",
            descriptionText: "Restore the default menu bar appearance.",
            pane: .menuBarAppearance,
            sectionKey: nil,
            sectionText: nil,
            keywords: ["reset", "appearance", "default"],
            property: nil
        ),
    ]
}
