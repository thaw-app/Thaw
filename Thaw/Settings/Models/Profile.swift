//
//  Profile.swift
//  Project: Thaw
//
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
    var customIceIconIsTemplate: Bool
    var useIceBar: Bool
    var useIceBarOnlyOnNotchedDisplay: Bool
    var iceBarLocation: IceBarLocation
    var iceBarLocationOnHotkey: Bool
    var showOnClick: Bool
    var showOnDoubleClick: Bool
    var showOnHover: Bool
    var showOnScroll: Bool
    var itemSpacingOffset: Double
    var autoRehide: Bool
    var rehideStrategyRawValue: Int
    var rehideInterval: TimeInterval

    @MainActor
    static func capture(from settings: GeneralSettings) -> GeneralSettingsSnapshot {
        GeneralSettingsSnapshot(
            showIceIcon: settings.showIceIcon,
            iceIcon: settings.iceIcon,
            customIceIconIsTemplate: settings.customIceIconIsTemplate,
            useIceBar: settings.useIceBar,
            useIceBarOnlyOnNotchedDisplay: settings.useIceBarOnlyOnNotchedDisplay,
            iceBarLocation: settings.iceBarLocation,
            iceBarLocationOnHotkey: settings.iceBarLocationOnHotkey,
            showOnClick: settings.showOnClick,
            showOnDoubleClick: settings.showOnDoubleClick,
            showOnHover: settings.showOnHover,
            showOnScroll: settings.showOnScroll,
            itemSpacingOffset: settings.itemSpacingOffset,
            autoRehide: settings.autoRehide,
            rehideStrategyRawValue: settings.rehideStrategy.rawValue,
            rehideInterval: settings.rehideInterval
        )
    }

    @MainActor
    func apply(to settings: GeneralSettings) {
        settings.showIceIcon = showIceIcon
        settings.iceIcon = iceIcon
        settings.customIceIconIsTemplate = customIceIconIsTemplate
        settings.useIceBar = useIceBar
        settings.useIceBarOnlyOnNotchedDisplay = useIceBarOnlyOnNotchedDisplay
        settings.iceBarLocation = iceBarLocation
        settings.iceBarLocationOnHotkey = iceBarLocationOnHotkey
        settings.showOnClick = showOnClick
        settings.showOnDoubleClick = showOnDoubleClick
        settings.showOnHover = showOnHover
        settings.showOnScroll = showOnScroll
        settings.itemSpacingOffset = itemSpacingOffset
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
    var showOnHoverDelay: TimeInterval
    var tooltipDelay: TimeInterval
    var showMenuBarTooltips: Bool
    var iconRefreshInterval: TimeInterval
    var enableDiagnosticLogging: Bool

    @MainActor
    static func capture(from settings: AdvancedSettings) -> AdvancedSettingsSnapshot {
        AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: settings.enableAlwaysHiddenSection,
            showAllSectionsOnUserDrag: settings.showAllSectionsOnUserDrag,
            sectionDividerStyle: settings.sectionDividerStyle.rawValue,
            hideApplicationMenus: settings.hideApplicationMenus,
            enableSecondaryContextMenu: settings.enableSecondaryContextMenu,
            showOnHoverDelay: settings.showOnHoverDelay,
            tooltipDelay: settings.tooltipDelay,
            showMenuBarTooltips: settings.showMenuBarTooltips,
            iconRefreshInterval: settings.iconRefreshInterval,
            enableDiagnosticLogging: settings.enableDiagnosticLogging
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
        settings.showOnHoverDelay = showOnHoverDelay
        settings.tooltipDelay = tooltipDelay
        settings.showMenuBarTooltips = showMenuBarTooltips
        settings.iconRefreshInterval = iconRefreshInterval
        settings.enableDiagnosticLogging = enableDiagnosticLogging
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
    var appearanceConfiguration: MenuBarAppearanceConfigurationV2
    var menuBarLayout: MenuBarLayoutSnapshot

    /// Returns lightweight metadata for this profile.
    var metadata: ProfileMetadata {
        ProfileMetadata(
            id: id,
            name: name,
            createdAt: createdAt,
            modifiedAt: modifiedAt
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
        case appearanceConfiguration
        case menuBarLayout
    }

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        modifiedAt: Date,
        generalSettings: GeneralSettingsSnapshot,
        advancedSettings: AdvancedSettingsSnapshot,
        hotkeys: [String: Data],
        displayConfigurations: [String: DisplayIceBarConfiguration],
        appearanceConfiguration: MenuBarAppearanceConfigurationV2,
        menuBarLayout: MenuBarLayoutSnapshot
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.generalSettings = generalSettings
        self.advancedSettings = advancedSettings
        self.hotkeys = hotkeys
        self.displayConfigurations = displayConfigurations
        self.appearanceConfiguration = appearanceConfiguration
        self.menuBarLayout = menuBarLayout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()

        generalSettings = try container.decodeIfPresent(
            GeneralSettingsSnapshot.self,
            forKey: .generalSettings
        ) ?? GeneralSettingsSnapshot(
            showIceIcon: Defaults.DefaultValue.showIceIcon,
            iceIcon: Defaults.DefaultValue.iceIcon,
            customIceIconIsTemplate: Defaults.DefaultValue.customIceIconIsTemplate,
            useIceBar: Defaults.DefaultValue.useIceBar,
            useIceBarOnlyOnNotchedDisplay: Defaults.DefaultValue.useIceBarOnlyOnNotchedDisplay,
            iceBarLocation: Defaults.DefaultValue.iceBarLocation,
            iceBarLocationOnHotkey: Defaults.DefaultValue.iceBarLocationOnHotkey,
            showOnClick: Defaults.DefaultValue.showOnClick,
            showOnDoubleClick: Defaults.DefaultValue.showOnDoubleClick,
            showOnHover: Defaults.DefaultValue.showOnHover,
            showOnScroll: Defaults.DefaultValue.showOnScroll,
            itemSpacingOffset: Defaults.DefaultValue.itemSpacingOffset,
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
            showOnHoverDelay: Defaults.DefaultValue.showOnHoverDelay,
            tooltipDelay: Defaults.DefaultValue.tooltipDelay,
            showMenuBarTooltips: Defaults.DefaultValue.showMenuBarTooltips,
            iconRefreshInterval: Defaults.DefaultValue.iconRefreshInterval,
            enableDiagnosticLogging: Defaults.DefaultValue.enableDiagnosticLogging
        )

        hotkeys = try container.decodeIfPresent(
            [String: Data].self,
            forKey: .hotkeys
        ) ?? [:]

        displayConfigurations = try container.decodeIfPresent(
            [String: DisplayIceBarConfiguration].self,
            forKey: .displayConfigurations
        ) ?? Defaults.DefaultValue.displayIceBarConfigurations

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
    }
}
