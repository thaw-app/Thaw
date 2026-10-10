//
//  SearchIndex.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsProperty

/// Links a search entry to the @Published property it represents on a
/// settings model, so the drift-guard test can assert every user-facing
/// property has a matching entry.
nonisolated enum SettingsProperty: Hashable {
    case general(String)
    case advanced(String)
}

// MARK: - SearchEntry

/// One searchable row in the settings search index.
///
/// The keys reuse the panes' literals, so no new translation keys appear.
/// Fuzzy matching uses the English source text, not the localized string.
///
/// Unchecked Sendable because LocalizedStringKey is not Sendable; every
/// field is an immutable let.
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

    var disclosure: AppNavigationState.SettingsDisclosure? {
        switch id {
        case "layout.spacers":
            .layoutSpacers
        // The two app-wide Thaw Bar toggles sit behind the page's disclosure.
        case "general.lockThawBarPosition", "general.thawBarLocationOnHotkey", "general.openHiddenItemsInMenuBar",
             "general.enableThawBarOnly", "general.showThawBarOnlyWithInlineReveal",
             "general.showThawBarOnlyLauncher":
            .thawBarAppWideOptions
        default:
            nil
        }
    }
}

nonisolated extension SearchEntry {
    /// Creates an entry whose title and section double as their localization
    /// keys.
    ///
    /// Pass each as a literal so Xcode extracts it into the catalog. Use the
    /// memberwise initializer when the key and matching text differ.
    init(
        id: String,
        title: String.LocalizationValue,
        descriptionText: String?,
        pane: SettingsNavigationIdentifier,
        section: String.LocalizationValue? = nil,
        keywords: [String],
        property: SettingsProperty?
    ) {
        let titleResource = LocalizedStringResource(title)
        self.init(
            id: id,
            titleKey: LocalizedStringKey(titleResource.key),
            titleText: titleResource.key,
            descriptionText: descriptionText,
            pane: pane,
            sectionKey: section.map { LocalizedStringKey(LocalizedStringResource($0).key) },
            sectionText: section.map { LocalizedStringResource($0).key },
            keywords: keywords,
            property: property
        )
    }
}

// MARK: - SearchIndex

nonisolated enum SearchIndex {
    /// Entries indexed on every supported macOS release.
    private static let sharedEntries: [SearchEntry] = paneEntries + generalEntries + revealEntries + advancedEntries
        + toolsEntries + displayEntries + hotkeyEntries + layoutEntries + appearanceEntries + aboutEntries + privacyEntries

    /// macOS 27-only settings rows, appended when the sidebar search UI is available.
    private static let platformEntries: [SearchEntry] = [
        SearchEntry(
            id: "advanced.enableExperimentalSystemItemHiding",
            title: "Allow hiding macOS system items",
            descriptionText: String(localized: "Allows items such as Clock, Control Center, and Siri to be moved into hidden sections."),
            pane: .menuBarLayout,
            keywords: ["system items", "clock", "control center", "siri", "hide", "macOS"],
            property: .advanced("enableExperimentalSystemItemHiding")
        ),
        SearchEntry(
            id: "advanced.menuBarArrangementMode",
            title: "Item arrangement",
            descriptionText: String(localized: "Let Thaw keep items in your Layout order, or arrange them yourself by ⌘-dragging in the menu bar."),
            pane: .menuBarLayout,
            section: "Sections",
            keywords: ["arrangement", "arrange", "manual", "automatic", "who", "order", "layout"],
            property: .advanced("menuBarArrangementMode")
        ),
        SearchEntry(
            id: "advanced.alwaysUseAppIconForMenuBarItems",
            title: "Use app icons instead of live previews",
            descriptionText: String(localized: "Show each item's app icon in the Thaw Bar and Layout instead of a live screenshot."),
            pane: .menuBarLayout,
            section: "More layout options",
            keywords: ["app icon", "live preview", "screenshot", "capture", "overflow", "notch", "advanced layout controls"],
            property: .advanced("alwaysUseAppIconForMenuBarItems")
        ),
        SearchEntry(
            id: "advanced.menuBarOrderFulfillmentTimeout",
            title: "Reorder timeout",
            descriptionText: String(localized: "How long Thaw waits for macOS to apply a menu bar reorder before continuing with remaining layout work."),
            pane: .menuBarLayout,
            section: "More layout options",
            keywords: ["reorder", "timeout", "wait", "layout", "seconds"],
            property: .advanced("menuBarOrderFulfillmentTimeout")
        ),
        // Spaces pane rows: agent-backed session state with no persisted
        // settings property, indexed so the pane's controls are findable.
        SearchEntry(
            id: "spaces.hideInThisSpace",
            title: "Hide the menu bar in this Space",
            descriptionText: String(localized: "Hides the system menu bar only while this Space is showing. Other Spaces keep their current behavior."),
            pane: .spaces,
            section: "This Space",
            keywords: ["hide", "space", "menu bar", "per-space", "desktop"],
            property: nil
        ),
        SearchEntry(
            id: "spaces.disableHoverReveal",
            title: "Disable hover reveal in this Space",
            descriptionText: String(localized: "Stops a hidden menu bar from sliding down when the pointer reaches the top edge of the screen in this Space."),
            pane: .spaces,
            section: "This Space",
            keywords: ["hover", "reveal", "auto show", "space", "top edge"],
            property: nil
        ),
        SearchEntry(
            id: "spaces.revealStripHeight",
            title: "Reveal strip height",
            descriptionText: String(localized: "How tall the invisible strip at the top of the screen is before a hidden menu bar reveals itself."),
            pane: .spaces,
            section: "This Space",
            keywords: ["reveal", "strip", "height", "edge", "hidden", "autohide"],
            property: nil
        ),
        SearchEntry(
            id: "spaces.fullScreenAppearanceEverywhere",
            title: "Use the full-screen menu bar appearance everywhere",
            descriptionText: String(localized: "Gives ordinary desktop Spaces the menu bar appearance macOS normally reserves for full-screen apps."),
            pane: .spaces,
            section: "All Spaces",
            keywords: ["fullscreen", "appearance", "everywhere", "spaces"],
            property: nil
        ),
        SearchEntry(
            id: "spaces.hideEverywhere",
            title: "Hide the menu bar in every Space",
            descriptionText: String(localized: "Hides the system menu bar in every context, full screen included."),
            pane: .spaces,
            section: "All Spaces",
            keywords: ["hide", "global", "every space", "menu bar"],
            property: nil
        ),
    ]

    /// All searchable settings entries, in pane order.
    ///
    /// Resolved once, since search reads it per keystroke.
    static let entries: [SearchEntry] = sharedEntries + platformEntries

    /// @Published property names that are intentionally absent from the
    /// index because they are deprecated, internal, or currently commented out
    /// of the UI. The drift-guard test allows these.
    private static let baseNonSearchableProperties: Set<SettingsProperty> = [
        .general("lastCustomThawIcon"),
        .general("useThawBar"),
        .general("useThawBarOnlyOnNotchedDisplay"),
        .general("thawBarLocation"),
        // An error channel, not a setting.
        .general("thawIconPersistenceError"),
        // Thaw Bar Only is unplugged for now; its switches are commented out.
        .general("enableThawBarOnly"),
        .general("showThawBarOnlyLauncher"),
        .general("showThawBarOnlyWithInlineReveal"),
        // The radius slider shows only under Round screen corners.
        .general("screenCornerRadius"),
        // Experimental toggles with no Settings UI.
        .advanced("enableExperimentalOverflowPrevention"),
        .advanced("enableTimerTakeover"),
        // Tuning kept out of Settings on purpose; settings URIs still reach it.
        .general("rehideStrategy"),
        .general("rehideInterval"),
        .advanced("swapOnThawIconClick"),
        .advanced("showAllSectionsOnUserDrag"),
        .advanced("showOnHoverDelay"),
        .advanced("tooltipDelay"),
        .advanced("iconRefreshInterval"),
    ]

    static var nonSearchableProperties: Set<SettingsProperty> {
        return baseNonSearchableProperties
    }

    /// Returns the entries that belong to the given pane.
    static func entries(for pane: SettingsNavigationIdentifier) -> [SearchEntry] {
        entries.filter { $0.pane == pane }
    }

    /// Lowest diffScore first (0 is a perfect match). Shares SearchRanker
    /// with menu bar item search so the two cannot drift.
    static func sortedByRelevance<T>(_ items: [(item: T, diffScore: Double)]) -> [T] {
        SearchRanker.sortedByRelevance(items)
    }
}
