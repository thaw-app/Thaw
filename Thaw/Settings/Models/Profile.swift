//
//  Profile.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - ProfileMetadata

/// Lightweight struct for listing profiles without loading full data.
struct ProfileMetadata: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    /// The display UUID this profile auto-activates for, or `nil` for manual-only.
    var associatedDisplayUUID: String?
    /// The cached display name, used when the display is disconnected.
    var associatedDisplayName: String?
}

// MARK: - GeneralSettingsSnapshot

/// A codable snapshot of all General settings properties.
struct GeneralSettingsSnapshot: Codable {
    var showIceIcon: Bool
    var iceIcon: ControlItemImageSet
    var lastCustomIceIcon: ControlItemImageSet?
    var customIceIconIsTemplate: Bool
    var useIceBar: Bool
    var useIceBarOnlyOnNotchedDisplay: Bool
    var iceBarLocation: IceBarLocation
    var iceBarLocationOnHotkey: Bool
    var showOnClick: Bool
    var showOnDoubleClick: Bool
    var showOnHover: Bool
    var showOnScroll: Bool
    var autoRehide: Bool
    var rehideStrategyRawValue: Int
    var rehideInterval: TimeInterval

    @MainActor
    static func capture(from settings: GeneralSettings) -> GeneralSettingsSnapshot {
        GeneralSettingsSnapshot(
            showIceIcon: settings.showIceIcon,
            iceIcon: settings.iceIcon,
            lastCustomIceIcon: settings.lastCustomIceIcon,
            customIceIconIsTemplate: settings.customIceIconIsTemplate,
            useIceBar: settings.useIceBar,
            useIceBarOnlyOnNotchedDisplay: settings.useIceBarOnlyOnNotchedDisplay,
            iceBarLocation: settings.iceBarLocation,
            iceBarLocationOnHotkey: settings.iceBarLocationOnHotkey,
            showOnClick: settings.showOnClick,
            showOnDoubleClick: settings.showOnDoubleClick,
            showOnHover: settings.showOnHover,
            showOnScroll: settings.showOnScroll,
            autoRehide: settings.autoRehide,
            rehideStrategyRawValue: settings.rehideStrategy.rawValue,
            rehideInterval: settings.rehideInterval
        )
    }

    @MainActor
    func apply(to settings: GeneralSettings) {
        settings.showIceIcon = showIceIcon
        settings.lastCustomIceIcon = lastCustomIceIcon
        settings.customIceIconIsTemplate = customIceIconIsTemplate
        settings.iceIcon = iceIcon
        settings.useIceBar = useIceBar
        settings.useIceBarOnlyOnNotchedDisplay = useIceBarOnlyOnNotchedDisplay
        settings.iceBarLocation = iceBarLocation
        settings.iceBarLocationOnHotkey = iceBarLocationOnHotkey
        settings.showOnClick = showOnClick
        settings.showOnDoubleClick = showOnDoubleClick
        settings.showOnHover = showOnHover
        settings.showOnScroll = showOnScroll
        settings.autoRehide = autoRehide
        if let strategy = RehideStrategy(rawValue: rehideStrategyRawValue) {
            settings.rehideStrategy = strategy
        }
        settings.rehideInterval = rehideInterval
    }
}

// MARK: - AdvancedSettingsSnapshot

/// A codable snapshot of all Advanced settings properties.
struct AdvancedSettingsSnapshot: Codable {
    var enableAlwaysHiddenSection: Bool
    var showAllSectionsOnUserDrag: Bool
    var sectionDividerStyle: Int
    var hideApplicationMenus: Bool
    var enableSecondaryContextMenu: Bool
    var enableSecondaryContextMenuQuit: Bool
    var showOnHoverDelay: TimeInterval
    var tooltipDelay: TimeInterval
    var showMenuBarTooltips: Bool
    var iconRefreshInterval: TimeInterval
    var enableDiagnosticLogging: Bool
    var useDoubleClickToShowAlwaysHiddenSection: Bool
    var useOptionClickToShowAlwaysHiddenSection: Bool
    var useLCSSortingOnNotchedDisplays: Bool
    var enableMenuBarItemOverflow: Bool
    var searchSectionOrder: [String]
    var searchIncludeVisible: Bool
    var searchIncludeHidden: Bool
    var searchIncludeAlwaysHidden: Bool

    @MainActor
    static func capture(from settings: AdvancedSettings) -> AdvancedSettingsSnapshot {
        AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: settings.enableAlwaysHiddenSection,
            showAllSectionsOnUserDrag: settings.showAllSectionsOnUserDrag,
            sectionDividerStyle: settings.sectionDividerStyle.rawValue,
            hideApplicationMenus: settings.hideApplicationMenus,
            enableSecondaryContextMenu: settings.enableSecondaryContextMenu,
            enableSecondaryContextMenuQuit: settings.enableSecondaryContextMenuQuit,
            showOnHoverDelay: settings.showOnHoverDelay,
            tooltipDelay: settings.tooltipDelay,
            showMenuBarTooltips: settings.showMenuBarTooltips,
            iconRefreshInterval: settings.iconRefreshInterval,
            enableDiagnosticLogging: settings.enableDiagnosticLogging,
            useDoubleClickToShowAlwaysHiddenSection: settings.useDoubleClickToShowAlwaysHiddenSection,
            useOptionClickToShowAlwaysHiddenSection: settings.useOptionClickToShowAlwaysHiddenSection,
            useLCSSortingOnNotchedDisplays: settings.useLCSSortingOnNotchedDisplays,
            enableMenuBarItemOverflow: settings.enableMenuBarItemOverflow,
            searchSectionOrder: settings.searchSectionOrder.map(\.rawValue),
            searchIncludeVisible: settings.searchIncludeVisible,
            searchIncludeHidden: settings.searchIncludeHidden,
            searchIncludeAlwaysHidden: settings.searchIncludeAlwaysHidden
        )
    }

    @MainActor
    func apply(to settings: AdvancedSettings) {
        settings.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        settings.showAllSectionsOnUserDrag = showAllSectionsOnUserDrag
        if let style = SectionDividerStyle(rawValue: sectionDividerStyle) {
            settings.sectionDividerStyle = style
        }
        settings.hideApplicationMenus = hideApplicationMenus
        settings.enableSecondaryContextMenu = enableSecondaryContextMenu
        settings.enableSecondaryContextMenuQuit = enableSecondaryContextMenuQuit
        settings.showOnHoverDelay = showOnHoverDelay
        settings.tooltipDelay = tooltipDelay
        settings.showMenuBarTooltips = showMenuBarTooltips
        settings.iconRefreshInterval = iconRefreshInterval
        settings.enableDiagnosticLogging = enableDiagnosticLogging
        settings.useDoubleClickToShowAlwaysHiddenSection = useDoubleClickToShowAlwaysHiddenSection
        settings.useOptionClickToShowAlwaysHiddenSection = useOptionClickToShowAlwaysHiddenSection
        settings.useLCSSortingOnNotchedDisplays = useLCSSortingOnNotchedDisplays
        settings.enableMenuBarItemOverflow = enableMenuBarItemOverflow
        settings.searchSectionOrder = AdvancedSettings.sanitizedSearchSectionOrder(from: searchSectionOrder)
        settings.searchIncludeVisible = searchIncludeVisible
        settings.searchIncludeHidden = searchIncludeHidden
        settings.searchIncludeAlwaysHidden = searchIncludeAlwaysHidden
    }

    enum CodingKeys: String, CodingKey {
        case enableAlwaysHiddenSection
        case showAllSectionsOnUserDrag
        case sectionDividerStyle
        case hideApplicationMenus
        case enableSecondaryContextMenu
        case enableSecondaryContextMenuQuit
        case showOnHoverDelay
        case tooltipDelay
        case showMenuBarTooltips
        case iconRefreshInterval
        case enableDiagnosticLogging
        case useDoubleClickToShowAlwaysHiddenSection
        case useOptionClickToShowAlwaysHiddenSection
        case useLCSSortingOnNotchedDisplays
        case enableMenuBarItemOverflow
        case searchSectionOrder
        case searchIncludeVisible
        case searchIncludeHidden
        case searchIncludeAlwaysHidden
    }

    init(
        enableAlwaysHiddenSection: Bool,
        showAllSectionsOnUserDrag: Bool,
        sectionDividerStyle: Int,
        hideApplicationMenus: Bool,
        enableSecondaryContextMenu: Bool,
        enableSecondaryContextMenuQuit: Bool,
        showOnHoverDelay: TimeInterval,
        tooltipDelay: TimeInterval,
        showMenuBarTooltips: Bool,
        iconRefreshInterval: TimeInterval,
        enableDiagnosticLogging: Bool,
        useDoubleClickToShowAlwaysHiddenSection: Bool,
        useOptionClickToShowAlwaysHiddenSection: Bool,
        useLCSSortingOnNotchedDisplays: Bool,
        enableMenuBarItemOverflow: Bool,
        searchSectionOrder: [String],
        searchIncludeVisible: Bool,
        searchIncludeHidden: Bool,
        searchIncludeAlwaysHidden: Bool
    ) {
        self.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        self.showAllSectionsOnUserDrag = showAllSectionsOnUserDrag
        self.sectionDividerStyle = sectionDividerStyle
        self.hideApplicationMenus = hideApplicationMenus
        self.enableSecondaryContextMenu = enableSecondaryContextMenu
        self.enableSecondaryContextMenuQuit = enableSecondaryContextMenuQuit
        self.showOnHoverDelay = showOnHoverDelay
        self.tooltipDelay = tooltipDelay
        self.showMenuBarTooltips = showMenuBarTooltips
        self.iconRefreshInterval = iconRefreshInterval
        self.enableDiagnosticLogging = enableDiagnosticLogging
        self.useDoubleClickToShowAlwaysHiddenSection = useDoubleClickToShowAlwaysHiddenSection
        self.useOptionClickToShowAlwaysHiddenSection = useOptionClickToShowAlwaysHiddenSection
        self.useLCSSortingOnNotchedDisplays = useLCSSortingOnNotchedDisplays
        self.enableMenuBarItemOverflow = enableMenuBarItemOverflow
        self.searchSectionOrder = searchSectionOrder
        self.searchIncludeVisible = searchIncludeVisible
        self.searchIncludeHidden = searchIncludeHidden
        self.searchIncludeAlwaysHidden = searchIncludeAlwaysHidden
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableAlwaysHiddenSection = try container.decodeIfPresent(
            Bool.self, forKey: .enableAlwaysHiddenSection
        ) ?? Defaults.DefaultValue.enableAlwaysHiddenSection
        showAllSectionsOnUserDrag = try container.decodeIfPresent(
            Bool.self, forKey: .showAllSectionsOnUserDrag
        ) ?? Defaults.DefaultValue.showAllSectionsOnUserDrag
        sectionDividerStyle = try container.decodeIfPresent(
            Int.self, forKey: .sectionDividerStyle
        ) ?? Defaults.DefaultValue.sectionDividerStyle.rawValue
        hideApplicationMenus = try container.decodeIfPresent(
            Bool.self, forKey: .hideApplicationMenus
        ) ?? Defaults.DefaultValue.hideApplicationMenus
        enableSecondaryContextMenu = try container.decodeIfPresent(
            Bool.self, forKey: .enableSecondaryContextMenu
        ) ?? Defaults.DefaultValue.enableSecondaryContextMenu
        enableSecondaryContextMenuQuit = try container.decodeIfPresent(
            Bool.self, forKey: .enableSecondaryContextMenuQuit
        ) ?? Defaults.DefaultValue.enableSecondaryContextMenuQuit
        showOnHoverDelay = try container.decodeIfPresent(
            TimeInterval.self, forKey: .showOnHoverDelay
        ) ?? Defaults.DefaultValue.showOnHoverDelay
        tooltipDelay = try container.decodeIfPresent(
            TimeInterval.self, forKey: .tooltipDelay
        ) ?? Defaults.DefaultValue.tooltipDelay
        showMenuBarTooltips = try container.decodeIfPresent(
            Bool.self, forKey: .showMenuBarTooltips
        ) ?? Defaults.DefaultValue.showMenuBarTooltips
        iconRefreshInterval = try container.decodeIfPresent(
            TimeInterval.self, forKey: .iconRefreshInterval
        ) ?? Defaults.DefaultValue.iconRefreshInterval
        enableDiagnosticLogging = try container.decodeIfPresent(
            Bool.self, forKey: .enableDiagnosticLogging
        ) ?? Defaults.DefaultValue.enableDiagnosticLogging
        useDoubleClickToShowAlwaysHiddenSection = try container.decodeIfPresent(
            Bool.self, forKey: .useDoubleClickToShowAlwaysHiddenSection
        ) ?? Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection
        useOptionClickToShowAlwaysHiddenSection = try container.decodeIfPresent(
            Bool.self, forKey: .useOptionClickToShowAlwaysHiddenSection
        ) ?? Defaults.DefaultValue.useOptionClickToShowAlwaysHiddenSection
        useLCSSortingOnNotchedDisplays = try container.decodeIfPresent(
            Bool.self, forKey: .useLCSSortingOnNotchedDisplays
        ) ?? Defaults.DefaultValue.useLCSSortingOnNotchedDisplays
        enableMenuBarItemOverflow = try container.decodeIfPresent(
            Bool.self, forKey: .enableMenuBarItemOverflow
        ) ?? Defaults.DefaultValue.enableMenuBarItemOverflow
        searchSectionOrder = try container.decodeIfPresent(
            [String].self, forKey: .searchSectionOrder
        ) ?? Defaults.DefaultValue.searchSectionOrder
        searchIncludeVisible = try container.decodeIfPresent(
            Bool.self, forKey: .searchIncludeVisible
        ) ?? Defaults.DefaultValue.searchIncludeVisible
        searchIncludeHidden = try container.decodeIfPresent(
            Bool.self, forKey: .searchIncludeHidden
        ) ?? Defaults.DefaultValue.searchIncludeHidden
        searchIncludeAlwaysHidden = try container.decodeIfPresent(
            Bool.self, forKey: .searchIncludeAlwaysHidden
        ) ?? Defaults.DefaultValue.searchIncludeAlwaysHidden
    }
}

// MARK: - MenuBarLayoutSnapshot

/// A codable snapshot of the menu bar item layout.
struct MenuBarLayoutSnapshot: Codable {
    var savedSectionOrder: [String: [String]]
    var pinnedHiddenBundleIDs: [String]
    var pinnedAlwaysHiddenBundleIDs: [String]
    var customNames: [String: String]

    /// Per-item section assignments keyed by uniqueIdentifier (namespace:title).
    /// Maps to section key strings: "visible", "hidden", "alwaysHidden".
    /// This is the primary source of truth for profile restore, as it handles
    /// apps like Control Center that share a single bundle ID across many items.
    var itemSectionMap: [String: String]?

    /// Ordered list of uniqueIdentifiers per section, capturing the visual
    /// order of items at save time. Used to restore within-section ordering.
    var itemOrder: [String: [String]]?

    /// Placement preference for the New Items badge (section and anchor).
    /// Absent in profiles saved before this field was introduced.
    var newItemsPlacement: MenuBarItemManager.NewItemsPlacement?

    /// Per-item hotkey bindings keyed by uniqueIdentifier (namespace:title).
    /// Each value is an encoded KeyCombination, matching the storage shape of
    /// the menuBarItemHotkeys default. Absent in profiles saved before this
    /// field was introduced.
    var itemHotkeys: [String: Data]?
}

// MARK: - ProfileContent

/// Groups all settings data for a profile, used to reduce init parameter count.
struct ProfileContent {
    var generalSettings: GeneralSettingsSnapshot
    var advancedSettings: AdvancedSettingsSnapshot
    var hotkeys: [String: Data]
    var displayConfigurations: [String: DisplayIceBarConfiguration]
    var globalDisplayConfiguration: DisplayIceBarConfiguration
    var confirmSpacingRelaunch: Bool
    var unconfirmedSpacingProfileScope: SpacingProfileSaveScope
    var appearanceConfiguration: MenuBarAppearanceConfigurationV2
    var menuBarLayout: MenuBarLayoutSnapshot
    var automation: ProfileAutomation?

    init(
        generalSettings: GeneralSettingsSnapshot,
        advancedSettings: AdvancedSettingsSnapshot,
        hotkeys: [String: Data],
        displayConfigurations: [String: DisplayIceBarConfiguration],
        globalDisplayConfiguration: DisplayIceBarConfiguration = Defaults.DefaultValue.globalDisplayConfiguration,
        confirmSpacingRelaunch: Bool = Defaults.DefaultValue.confirmSpacingRelaunch,
        unconfirmedSpacingProfileScope: SpacingProfileSaveScope = Defaults.DefaultValue.unconfirmedSpacingProfileScope,
        appearanceConfiguration: MenuBarAppearanceConfigurationV2,
        menuBarLayout: MenuBarLayoutSnapshot,
        automation: ProfileAutomation? = nil
    ) {
        self.generalSettings = generalSettings
        self.advancedSettings = advancedSettings
        self.hotkeys = hotkeys
        self.displayConfigurations = displayConfigurations
        self.globalDisplayConfiguration = globalDisplayConfiguration
        self.confirmSpacingRelaunch = confirmSpacingRelaunch
        self.unconfirmedSpacingProfileScope = unconfirmedSpacingProfileScope
        self.appearanceConfiguration = appearanceConfiguration
        self.menuBarLayout = menuBarLayout
        self.automation = automation
    }
}

// MARK: - Profile

/// A complete settings profile that can be saved to and restored from disk.
struct Profile: Codable, Identifiable {
    let id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var generalSettings: GeneralSettingsSnapshot
    var advancedSettings: AdvancedSettingsSnapshot
    var hotkeys: [String: Data]
    var displayConfigurations: [String: DisplayIceBarConfiguration]
    var globalDisplayConfiguration: DisplayIceBarConfiguration
    var confirmSpacingRelaunch: Bool
    var unconfirmedSpacingProfileScope: SpacingProfileSaveScope
    var appearanceConfiguration: MenuBarAppearanceConfigurationV2
    var menuBarLayout: MenuBarLayoutSnapshot
    var automation: ProfileAutomation?

    /// Returns lightweight metadata for this profile.
    var metadata: ProfileMetadata {
        ProfileMetadata(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }

    /// Returns the settings content of this profile.
    var content: ProfileContent {
        ProfileContent(
            generalSettings: generalSettings,
            advancedSettings: advancedSettings,
            hotkeys: hotkeys,
            displayConfigurations: displayConfigurations,
            globalDisplayConfiguration: globalDisplayConfiguration,
            confirmSpacingRelaunch: confirmSpacingRelaunch,
            unconfirmedSpacingProfileScope: unconfirmedSpacingProfileScope,
            appearanceConfiguration: appearanceConfiguration,
            menuBarLayout: menuBarLayout,
            automation: automation
        )
    }

    // MARK: - Forward-Compatible Decoding

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case modifiedAt
        case generalSettings
        case advancedSettings
        case hotkeys
        case displayConfigurations
        case globalDisplayConfiguration
        case confirmSpacingRelaunch
        case unconfirmedSpacingProfileScope
        case appearanceConfiguration
        case menuBarLayout
        case automation
    }

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        content: ProfileContent
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.generalSettings = content.generalSettings
        self.advancedSettings = content.advancedSettings
        self.hotkeys = content.hotkeys
        self.displayConfigurations = content.displayConfigurations
        self.globalDisplayConfiguration = content.globalDisplayConfiguration
        self.confirmSpacingRelaunch = content.confirmSpacingRelaunch
        self.unconfirmedSpacingProfileScope = content.unconfirmedSpacingProfileScope
        self.appearanceConfiguration = content.appearanceConfiguration
        self.menuBarLayout = content.menuBarLayout
        self.automation = content.automation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? String(localized: "Untitled")
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()

        generalSettings = try container.decodeIfPresent(
            GeneralSettingsSnapshot.self,
            forKey: .generalSettings
        ) ?? GeneralSettingsSnapshot(
            showIceIcon: Defaults.DefaultValue.showIceIcon,
            iceIcon: Defaults.DefaultValue.iceIcon,
            lastCustomIceIcon: nil,
            customIceIconIsTemplate: Defaults.DefaultValue.customIceIconIsTemplate,
            useIceBar: Defaults.DefaultValue.useIceBar,
            useIceBarOnlyOnNotchedDisplay: Defaults.DefaultValue.useIceBarOnlyOnNotchedDisplay,
            iceBarLocation: Defaults.DefaultValue.iceBarLocation,
            iceBarLocationOnHotkey: Defaults.DefaultValue.iceBarLocationOnHotkey,
            showOnClick: Defaults.DefaultValue.showOnClick,
            showOnDoubleClick: Defaults.DefaultValue.showOnDoubleClick,
            showOnHover: Defaults.DefaultValue.showOnHover,
            showOnScroll: Defaults.DefaultValue.showOnScroll,
            autoRehide: Defaults.DefaultValue.autoRehide,
            rehideStrategyRawValue: Defaults.DefaultValue.rehideStrategy.rawValue,
            rehideInterval: Defaults.DefaultValue.rehideInterval
        )

        advancedSettings = try container.decodeIfPresent(
            AdvancedSettingsSnapshot.self,
            forKey: .advancedSettings
        ) ?? AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: Defaults.DefaultValue.enableAlwaysHiddenSection,
            showAllSectionsOnUserDrag: Defaults.DefaultValue.showAllSectionsOnUserDrag,
            sectionDividerStyle: Defaults.DefaultValue.sectionDividerStyle.rawValue,
            hideApplicationMenus: Defaults.DefaultValue.hideApplicationMenus,
            enableSecondaryContextMenu: Defaults.DefaultValue.enableSecondaryContextMenu,
            enableSecondaryContextMenuQuit: Defaults.DefaultValue.enableSecondaryContextMenuQuit,
            showOnHoverDelay: Defaults.DefaultValue.showOnHoverDelay,
            tooltipDelay: Defaults.DefaultValue.tooltipDelay,
            showMenuBarTooltips: Defaults.DefaultValue.showMenuBarTooltips,
            iconRefreshInterval: Defaults.DefaultValue.iconRefreshInterval,
            enableDiagnosticLogging: Defaults.DefaultValue.enableDiagnosticLogging,
            useDoubleClickToShowAlwaysHiddenSection: Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection,
            useOptionClickToShowAlwaysHiddenSection: Defaults.DefaultValue.useOptionClickToShowAlwaysHiddenSection,
            useLCSSortingOnNotchedDisplays: Defaults.DefaultValue.useLCSSortingOnNotchedDisplays,
            enableMenuBarItemOverflow: Defaults.DefaultValue.enableMenuBarItemOverflow,
            searchSectionOrder: Defaults.DefaultValue.searchSectionOrder,
            searchIncludeVisible: Defaults.DefaultValue.searchIncludeVisible,
            searchIncludeHidden: Defaults.DefaultValue.searchIncludeHidden,
            searchIncludeAlwaysHidden: Defaults.DefaultValue.searchIncludeAlwaysHidden
        )

        hotkeys = try container.decodeIfPresent(
            [String: Data].self,
            forKey: .hotkeys
        ) ?? [:]

        displayConfigurations = try container.decodeIfPresent(
            [String: DisplayIceBarConfiguration].self,
            forKey: .displayConfigurations
        ) ?? Defaults.DefaultValue.displayIceBarConfigurations

        globalDisplayConfiguration = try container.decodeIfPresent(
            DisplayIceBarConfiguration.self,
            forKey: .globalDisplayConfiguration
        ) ?? Defaults.DefaultValue.globalDisplayConfiguration

        confirmSpacingRelaunch = try container.decodeIfPresent(
            Bool.self,
            forKey: .confirmSpacingRelaunch
        ) ?? Defaults.DefaultValue.confirmSpacingRelaunch

        unconfirmedSpacingProfileScope = try container.decodeIfPresent(
            SpacingProfileSaveScope.self,
            forKey: .unconfirmedSpacingProfileScope
        ) ?? Defaults.DefaultValue.unconfirmedSpacingProfileScope

        appearanceConfiguration = try container.decodeIfPresent(
            MenuBarAppearanceConfigurationV2.self,
            forKey: .appearanceConfiguration
        ) ?? Defaults.DefaultValue.menuBarAppearanceConfigurationV2

        menuBarLayout = try container.decodeIfPresent(
            MenuBarLayoutSnapshot.self,
            forKey: .menuBarLayout
        ) ?? MenuBarLayoutSnapshot(
            savedSectionOrder: [:],
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:]
        )

        automation = try container.decodeIfPresent(
            ProfileAutomation.self,
            forKey: .automation
        )
    }
}

// MARK: - ProfileExportEntry

/// A single profile bundled with its metadata for export/import.
/// Preserves display associations that live on the manifest.
struct ProfileExportEntry: Codable {
    var profile: Profile
    var associatedDisplayUUID: String?
    var associatedDisplayName: String?
}

/// Wrapper for exporting multiple profiles as a single file.
struct ProfileExportBundle: Codable {
    var version: Int = 1
    var entries: [ProfileExportEntry]
}
