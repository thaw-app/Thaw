//
//  SearchIndex.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsProperty

/// Links a search entry to the property it represents on a page's settings
/// model, so the drift-guard test can assert every user-facing property has
/// a matching entry.
nonisolated enum SettingsProperty: Hashable {
    case general(String)
    case layout(String)
    case visibility(String)
    case thawBar(String)
    case appearance(String)
    case spaces(String)
    case privacy(String)
    case tools(String)
    case widgets(String)
}

// MARK: - SearchEntry

/// One searchable row in the settings search index.
///
/// The keys reuse the panes' literals, so no new translation keys appear.
/// Fuzzy matching uses the English source text, not the localized string.
///
/// Unchecked Sendable because LocalizedStringKey is not Sendable; every
/// field is an immutable let, except the flag a row is filtered by.
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
    /// The row only exists while diagnostic logging is on, so search hides the
    /// entry with the row rather than jumping to nothing.
    var needsDiagnosticLogging = false

    var disclosure: AppNavigationState.SettingsDisclosure? {
        switch id {
        case "layout.spacers":
            .layoutSpacers
        // Layout's Options tab.
        case "advanced.menuBarArrangementMode", "advanced.enableAlwaysHiddenSection", "advanced.sectionDividerStyle", "layout.showAllSectionsOnUserDrag",
             "advanced.enableNativeAppHiding", "advanced.enableMenuBarItemOverflow",
             "advanced.alwaysUseAppIconForMenuBarItems", "layout.resetMenuBarLayout":
            .layoutOptions
        case "layout.replaceControlCenterItems":
            .layoutAppleItems
        case "appearance.shapeFill":
            .appearanceInsideShape
        case "appearance.background":
            .appearanceBehindShape
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
        property: SettingsProperty?,
        needsDiagnosticLogging: Bool = false
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
            property: property,
            needsDiagnosticLogging: needsDiagnosticLogging
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
            id: "advanced.menuBarArrangementMode",
            title: "Item arrangement",
            descriptionText: String(localized: "Let \(Constants.displayName) keep items in your Layout order, or arrange them yourself by ⌘-dragging in the menu bar."),
            pane: .menuBarLayout,
            section: "Sections",
            keywords: ["arrangement", "arrange", "manual", "automatic", "who", "order", "layout"],
            property: .layout("menuBarArrangementMode")
        ),
        SearchEntry(
            id: "advanced.alwaysUseAppIconForMenuBarItems",
            title: "Use app icons instead of live previews",
            descriptionText: String(localized: "Show each item's app icon in the Thaw Bar and Layout instead of a live screenshot."),
            pane: .menuBarLayout,
            section: "Overflow and previews",
            keywords: ["app icon", "live preview", "screenshot", "capture", "overflow", "notch", "advanced layout controls"],
            property: .layout("alwaysUseAppIconForMenuBarItems")
        ),
        SearchEntry(
            id: "layout.captureHiddenItems",
            title: "Capture hidden items",
            descriptionText: String(localized: "Takes new pictures of your Hidden and Always Hidden items, for example when they show app icons instead."),
            pane: .menuBarLayout,
            section: "Layout",
            keywords: ["capture", "screenshot", "picture", "sync", "images", "hidden", "always hidden", "icons", "app icon"],
            property: nil
        ),
        // Displays › Spaces rows: stored by SpaceMenuBarKeeper rather than a
        // settings property, indexed so the pane's controls are findable.
        SearchEntry(
            id: "spaces.hideInThisSpace",
            title: "Hide the menu bar",
            descriptionText: String(localized: "Hides the system menu bar while this Space is showing, or in every Space."),
            pane: .displays,
            section: "This Space",
            keywords: ["hide", "space", "menu bar", "per-space", "desktop", "global", "every space", "everywhere"],
            property: nil
        ),
        SearchEntry(
            id: "spaces.disableHoverReveal",
            title: "Disable hover reveal in this Space",
            descriptionText: String(localized: "Stops a hidden menu bar from sliding down when the pointer reaches the top edge of the screen in this Space."),
            pane: .displays,
            section: "This Space",
            keywords: ["hover", "reveal", "auto show", "space", "top edge"],
            property: nil
        ),
        SearchEntry(
            id: "spaces.revealStripHeight",
            title: "Reveal strip height",
            descriptionText: String(localized: "How tall the invisible strip at the top of the screen is before a hidden menu bar reveals itself."),
            pane: .displays,
            section: "This Space",
            keywords: ["reveal", "strip", "height", "edge", "hidden", "autohide"],
            property: nil
        ),
        SearchEntry(
            id: "spaces.showSpaceIndicator",
            title: "Show the current Space in the menu bar",
            descriptionText: String(localized: "Adds a menu bar item with the name of the Space you're in. Its menu lists the Spaces on each display."),
            pane: .displays,
            section: "Space indicator",
            keywords: ["space", "desktop", "indicator", "current space", "mission control", "number"],
            property: .spaces("showSpaceIndicator")
        ),
        SearchEntry(
            id: "spaces.fullScreenAppearanceEverywhere",
            title: "Use the full-screen menu bar appearance everywhere",
            descriptionText: String(localized: "Gives ordinary desktop Spaces the menu bar appearance macOS normally reserves for full-screen apps."),
            pane: .displays,
            section: "All Spaces",
            keywords: ["fullscreen", "appearance", "everywhere", "spaces"],
            property: nil
        ),
    ]

    /// All searchable settings entries, in pane order.
    ///
    /// Resolved once, since search reads it per keystroke.
    static let entries: [SearchEntry] = sharedEntries + platformEntries

    static func entry(withID id: String) -> SearchEntry? {
        entries.first { $0.id == id }
    }

    /// @Published property names that are intentionally absent from the
    /// index because they are deprecated, internal, or currently commented out
    /// of the UI. The drift-guard test allows these.
    static let nonSearchableProperties: Set<SettingsProperty> = [
        .general("lastCustomThawIcon"),
        .thawBar("useThawBar"),
        .thawBar("useThawBarOnlyOnNotchedDisplay"),
        .thawBar("thawBarLocation"),
        // An error channel, not a setting.
        .general("thawIconPersistenceError"),
        // The radius slider shows only under Round screen corners.
        .appearance("screenCornerRadius"),
        // Its switch is on Simple Mode's one page, which has no search.
        .general("simpleModeShowsPreview"),
        // Shown under Section divider style only while Custom is chosen; search finds that.
        .layout("customSectionDividerImage"),
        .layout("customSectionDividerIsTemplate"),
        // Its row is commented out of Layout: the timeout has no effect on macOS 27.
        .layout("menuBarOrderFulfillmentTimeout"),
        // Set by Replace Control Center items, indexed under layout.enableModuleStandIns.
        .layout("enableTimeMachineTakeover"),
        .layout("enableTextInputTakeover"),
        .layout("skippedModuleStandIns"),
        // Experimental toggles with no Settings UI.
        .layout("enableExperimentalOverflowPrevention"),
        .layout("enableTimerTakeover"),
        // Set by Hide items again, indexed under visibility.autoRehide.
        .visibility("rehideStrategy"),
        .visibility("rehideInterval"),
        // Tuning kept out of Settings on purpose; settings URIs still reach it.
        .layout("iconRefreshInterval"),
        // Shown under the alerts switch, which search finds.
        .visibility("recordingWatchScreen"),
        .visibility("recordingWatchPlacement"),
        // Under Apps that change settings, which the pane entry finds; the
        // allowed apps are a list, not a setting.
        .privacy("isSettingsURIEnabled"),
        .privacy("whitelistedApps"),
    ]

    /// Returns the entries that belong to the given pane.
    static func entries(for pane: SettingsNavigationIdentifier) -> [SearchEntry] {
        entries.filter { $0.pane == pane }
    }
}
