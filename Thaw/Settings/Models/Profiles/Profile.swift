//
//  Profile.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import ThawModuleKit

// MARK: - ProfileMetadata

/// Lightweight struct for listing profiles without loading full data.
nonisolated struct ProfileMetadata: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    /// The display UUID this profile auto-activates for, or nil for manual-only.
    var associatedDisplayUUID: String?
    /// The cached display name, used when the display is disconnected.
    var associatedDisplayName: String?
    /// The reboot-stable key of the Space this profile auto-activates for,
    /// or nil if manual-only. See Bridging.getSpacePersistentKeys().
    var associatedSpaceKey: String?
    /// The user-facing label for the associated Space. Spaces have no system
    /// name, so this is the label current when the association was made.
    var associatedSpaceName: String?
    /// Whether drags and Layout edits are saved into this profile while it is
    /// active. Nil in manifests written before the switch, which reads as on.
    var keepsLayoutChangesSetting: Bool?
    /// Whether Thaw applies this profile's layout again when it starts with
    /// the profile already active. Nil reads as off.
    var reappliesAtLaunchSetting: Bool?

    var keepsLayoutChanges: Bool {
        keepsLayoutChangesSetting ?? true
    }

    var reappliesAtLaunch: Bool {
        reappliesAtLaunchSetting ?? false
    }
}

// MARK: - GeneralSettingsSnapshot

/// A codable snapshot of all General settings properties.
nonisolated struct GeneralSettingsSnapshot: Codable {
    var showThawIcon: Bool
    var thawIcon: ControlItemImageSet
    var lastCustomThawIcon: ControlItemImageSet?
    var customThawIconIsTemplate: Bool
    var useThawBar: Bool
    var useThawBarOnlyOnNotchedDisplay: Bool
    var thawBarLocation: ThawBarLocation
    var thawBarLocationOnHotkey: Bool
    var showOnClick: Bool
    var showOnHover: Bool
    var showOnScroll: Bool
    var autoRehide: Bool
    var rehideStrategyRawValue: Int
    var rehideInterval: TimeInterval
    var tempShowInterval: TimeInterval

    /// The value every field takes when a profile predates it.
    static let defaults = GeneralSettingsSnapshot(
        showThawIcon: Defaults.DefaultValue.showThawIcon,
        thawIcon: Defaults.DefaultValue.thawIcon,
        lastCustomThawIcon: nil,
        customThawIconIsTemplate: Defaults.DefaultValue.customThawIconIsTemplate,
        useThawBar: Defaults.DefaultValue.useThawBar,
        useThawBarOnlyOnNotchedDisplay: Defaults.DefaultValue.useThawBarOnlyOnNotchedDisplay,
        thawBarLocation: Defaults.DefaultValue.thawBarLocation,
        thawBarLocationOnHotkey: Defaults.DefaultValue.thawBarLocationOnHotkey,
        showOnClick: Defaults.DefaultValue.showOnClick,
        showOnHover: Defaults.DefaultValue.showOnHover,
        showOnScroll: Defaults.DefaultValue.showOnScroll,
        autoRehide: Defaults.DefaultValue.autoRehide,
        rehideStrategyRawValue: Defaults.DefaultValue.rehideStrategy.rawValue,
        rehideInterval: Defaults.DefaultValue.rehideInterval,
        tempShowInterval: Defaults.DefaultValue.tempShowInterval
    )

    @MainActor
    static func capture(from settings: AppSettings) -> GeneralSettingsSnapshot {
        GeneralSettingsSnapshot(
            showThawIcon: settings.general.showThawIcon,
            thawIcon: settings.general.thawIcon,
            lastCustomThawIcon: settings.general.lastCustomThawIcon,
            customThawIconIsTemplate: settings.general.customThawIconIsTemplate,
            useThawBar: settings.thawBar.useThawBar,
            useThawBarOnlyOnNotchedDisplay: settings.thawBar.useThawBarOnlyOnNotchedDisplay,
            thawBarLocation: settings.thawBar.thawBarLocation,
            thawBarLocationOnHotkey: settings.thawBar.thawBarLocationOnHotkey,
            showOnClick: settings.visibility.showOnClick,
            showOnHover: settings.visibility.showOnHover,
            showOnScroll: settings.visibility.showOnScroll,
            autoRehide: settings.visibility.autoRehide,
            rehideStrategyRawValue: settings.visibility.rehideStrategy.rawValue,
            rehideInterval: settings.visibility.rehideInterval,
            tempShowInterval: settings.visibility.tempShowInterval
        )
    }

    @MainActor
    func apply(to settings: AppSettings) {
        settings.general.showThawIcon = showThawIcon
        settings.general.lastCustomThawIcon = lastCustomThawIcon
        settings.general.customThawIconIsTemplate = customThawIconIsTemplate
        settings.general.thawIcon = thawIcon
        settings.thawBar.useThawBar = useThawBar
        settings.thawBar.useThawBarOnlyOnNotchedDisplay = useThawBarOnlyOnNotchedDisplay
        settings.thawBar.thawBarLocation = thawBarLocation
        settings.thawBar.thawBarLocationOnHotkey = thawBarLocationOnHotkey
        settings.visibility.showOnClick = showOnClick
        settings.visibility.showOnHover = showOnHover
        settings.visibility.showOnScroll = showOnScroll
        settings.visibility.autoRehide = autoRehide
        if let strategy = RehideStrategy(rawValue: rehideStrategyRawValue) {
            settings.visibility.rehideStrategy = strategy
        }
        settings.visibility.rehideInterval = rehideInterval
        settings.visibility.tempShowInterval = tempShowInterval
    }

    enum CodingKeys: String, CodingKey {
        // The Ice-era key strings are pinned: profiles already written to
        // disk use them, and changing them would silently drop settings.
        case showThawIcon = "showIceIcon"
        case thawIcon = "iceIcon"
        case lastCustomThawIcon = "lastCustomIceIcon"
        case customThawIconIsTemplate = "customIceIconIsTemplate"
        case useThawBar = "useIceBar"
        case useThawBarOnlyOnNotchedDisplay = "useIceBarOnlyOnNotchedDisplay"
        case thawBarLocation = "iceBarLocation"
        case thawBarLocationOnHotkey = "iceBarLocationOnHotkey"
        case showOnClick
        case showOnHover
        case showOnScroll
        case autoRehide
        case rehideStrategyRawValue
        case rehideInterval
        case tempShowInterval
    }
}

nonisolated extension GeneralSettingsSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showThawIcon = try container.decode(.showThawIcon, default: Self.defaults.showThawIcon)
        thawIcon = try container.decode(.thawIcon, default: Self.defaults.thawIcon)
        lastCustomThawIcon = try container.decodeIfPresent(
            ControlItemImageSet.self, forKey: .lastCustomThawIcon
        )
        customThawIconIsTemplate = try container.decode(
            .customThawIconIsTemplate, default: Self.defaults.customThawIconIsTemplate
        )
        useThawBar = try container.decode(.useThawBar, default: Self.defaults.useThawBar)
        useThawBarOnlyOnNotchedDisplay = try container.decode(
            .useThawBarOnlyOnNotchedDisplay, default: Self.defaults.useThawBarOnlyOnNotchedDisplay
        )
        thawBarLocation = try container.decode(
            .thawBarLocation, default: Self.defaults.thawBarLocation
        )
        thawBarLocationOnHotkey = try container.decode(
            .thawBarLocationOnHotkey, default: Self.defaults.thawBarLocationOnHotkey
        )
        showOnClick = try container.decode(.showOnClick, default: Self.defaults.showOnClick)
        showOnHover = try container.decode(.showOnHover, default: Self.defaults.showOnHover)
        showOnScroll = try container.decode(.showOnScroll, default: Self.defaults.showOnScroll)
        autoRehide = try container.decode(.autoRehide, default: Self.defaults.autoRehide)
        rehideStrategyRawValue = try container.decode(
            .rehideStrategyRawValue, default: Self.defaults.rehideStrategyRawValue
        )
        rehideInterval = try container.decode(.rehideInterval, default: Self.defaults.rehideInterval)
        tempShowInterval = try container.decode(
            .tempShowInterval, default: Self.defaults.tempShowInterval
        )
    }
}

// MARK: - AdvancedSettingsSnapshot

/// A codable snapshot of all Advanced settings properties.
nonisolated struct AdvancedSettingsSnapshot: Codable {
    var enableAlwaysHiddenSection: Bool
    var showAllSectionsOnUserDrag: Bool
    var sectionDividerStyle: Int
    var hideApplicationMenus: Bool
    var enableSecondaryContextMenu: Bool
    var showOnHoverDelay: TimeInterval
    var tooltipDelay: TimeInterval
    var showMenuBarTooltips: Bool
    var iconRefreshInterval: TimeInterval
    var autoZenWhileSharingScreen: Bool
    var enableDiagnosticLogging: Bool
    var enableMenuBarItemOverflow: Bool
    // Apple-item hiding follows the hiding method, which profiles do not switch, so older profiles' value is ignored.

    /// The value every field takes when a profile predates it.
    static let defaults = AdvancedSettingsSnapshot(
        enableAlwaysHiddenSection: Defaults.DefaultValue.enableAlwaysHiddenSection,
        showAllSectionsOnUserDrag: Defaults.DefaultValue.showAllSectionsOnUserDrag,
        sectionDividerStyle: Defaults.DefaultValue.sectionDividerStyle.rawValue,
        hideApplicationMenus: Defaults.DefaultValue.hideApplicationMenus,
        enableSecondaryContextMenu: Defaults.DefaultValue.enableSecondaryContextMenu,
        showOnHoverDelay: Defaults.DefaultValue.showOnHoverDelay,
        tooltipDelay: Defaults.DefaultValue.tooltipDelay,
        showMenuBarTooltips: Defaults.DefaultValue.showMenuBarTooltips,
        iconRefreshInterval: Defaults.DefaultValue.iconRefreshInterval,
        autoZenWhileSharingScreen: Defaults.DefaultValue.autoZenWhileSharingScreen,
        enableDiagnosticLogging: Defaults.DefaultValue.enableDiagnosticLogging,
        enableMenuBarItemOverflow: Defaults.DefaultValue.enableMenuBarItemOverflow
    )

    @MainActor
    static func capture(from settings: AppSettings) -> AdvancedSettingsSnapshot {
        AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: settings.layout.enableAlwaysHiddenSection,
            showAllSectionsOnUserDrag: settings.layout.showAllSectionsOnUserDrag,
            sectionDividerStyle: settings.layout.sectionDividerStyle.rawValue,
            hideApplicationMenus: settings.general.hideApplicationMenus,
            enableSecondaryContextMenu: settings.general.enableSecondaryContextMenu,
            showOnHoverDelay: settings.visibility.showOnHoverDelay,
            tooltipDelay: settings.visibility.tooltipDelay,
            showMenuBarTooltips: settings.visibility.showMenuBarTooltips,
            iconRefreshInterval: settings.layout.iconRefreshInterval,
            autoZenWhileSharingScreen: settings.visibility.autoZenWhileSharingScreen,
            enableDiagnosticLogging: settings.tools.enableDiagnosticLogging,
            enableMenuBarItemOverflow: settings.layout.enableMenuBarItemOverflow
        )
    }

    @MainActor
    func apply(to settings: AppSettings) {
        settings.layout.enableAlwaysHiddenSection = enableAlwaysHiddenSection
        settings.layout.showAllSectionsOnUserDrag = showAllSectionsOnUserDrag
        if let style = SectionDividerStyle(rawValue: sectionDividerStyle) {
            settings.layout.sectionDividerStyle = style
        }
        settings.general.hideApplicationMenus = hideApplicationMenus
        settings.general.enableSecondaryContextMenu = enableSecondaryContextMenu
        settings.visibility.showOnHoverDelay = showOnHoverDelay
        settings.visibility.tooltipDelay = tooltipDelay
        settings.visibility.showMenuBarTooltips = showMenuBarTooltips
        settings.layout.iconRefreshInterval = iconRefreshInterval
        settings.visibility.autoZenWhileSharingScreen = autoZenWhileSharingScreen
        settings.tools.enableDiagnosticLogging = enableDiagnosticLogging
        settings.layout.enableMenuBarItemOverflow = enableMenuBarItemOverflow
    }
}

nonisolated extension AdvancedSettingsSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableAlwaysHiddenSection = try container.decode(
            .enableAlwaysHiddenSection, default: Self.defaults.enableAlwaysHiddenSection
        )
        showAllSectionsOnUserDrag = try container.decode(
            .showAllSectionsOnUserDrag, default: Self.defaults.showAllSectionsOnUserDrag
        )
        sectionDividerStyle = try container.decode(
            .sectionDividerStyle, default: Self.defaults.sectionDividerStyle
        )
        hideApplicationMenus = try container.decode(
            .hideApplicationMenus, default: Self.defaults.hideApplicationMenus
        )
        enableSecondaryContextMenu = try container.decode(
            .enableSecondaryContextMenu, default: Self.defaults.enableSecondaryContextMenu
        )
        showOnHoverDelay = try container.decode(
            .showOnHoverDelay, default: Self.defaults.showOnHoverDelay
        )
        tooltipDelay = try container.decode(.tooltipDelay, default: Self.defaults.tooltipDelay)
        showMenuBarTooltips = try container.decode(
            .showMenuBarTooltips, default: Self.defaults.showMenuBarTooltips
        )
        iconRefreshInterval = try container.decode(
            .iconRefreshInterval, default: Self.defaults.iconRefreshInterval
        )
        autoZenWhileSharingScreen = try container.decode(
            .autoZenWhileSharingScreen, default: Self.defaults.autoZenWhileSharingScreen
        )
        enableDiagnosticLogging = try container.decode(
            .enableDiagnosticLogging, default: Self.defaults.enableDiagnosticLogging
        )
        enableMenuBarItemOverflow = try container.decode(
            .enableMenuBarItemOverflow, default: Self.defaults.enableMenuBarItemOverflow
        )
    }
}

// MARK: - MenuBarLayoutSnapshot

/// A codable snapshot of the menu bar item layout.
nonisolated struct MenuBarLayoutSnapshot: Codable {
    var savedSectionOrder: [String: [String]]
    var pinnedHiddenBundleIDs: [String]
    var pinnedAlwaysHiddenBundleIDs: [String]
    var customNames: [String: String]

    /// Section key ("visible", "hidden", "alwaysHidden") per uniqueIdentifier.
    /// The source of truth on restore, since apps like Control Center share
    /// one bundle ID across many items.
    var itemSectionMap: [String: String]?

    /// Per-section order of uniqueIdentifiers at save time.
    var itemOrder: [String: [String]]?

    /// Nil in older profiles.
    var newItemsPlacement: MenuBarItemManager.NewItemsPlacement?

    /// Encoded KeyCombination per uniqueIdentifier, the same shape as the
    /// menuBarItemHotkeys default. Nil in older profiles.
    var itemHotkeys: [String: Data]?

    /// Nil in older profiles, meaning no groups.
    var itemGroups: MenuBarItemGroupSet?
}

// MARK: - ProfileContent

/// Groups all settings data for a profile, used to reduce init parameter count.
nonisolated struct ProfileContent {
    var generalSettings: GeneralSettingsSnapshot
    var advancedSettings: AdvancedSettingsSnapshot
    var hotkeys: [String: Data]
    var displayConfigurations: [String: DisplayThawBarConfiguration]
    var globalDisplayConfiguration: DisplayThawBarConfiguration = Defaults.DefaultValue.globalDisplayConfiguration
    var confirmSpacingRelaunch: Bool = Defaults.DefaultValue.confirmSpacingRelaunch
    var unconfirmedSpacingProfileScope: SpacingProfileSaveScope = Defaults.DefaultValue.unconfirmedSpacingProfileScope
    /// Nil in older profiles, which leave the current mode alone when applied.
    var spacingApplyMode: SpacingApplyMode?
    var appearanceConfiguration: MenuBarAppearanceConfigurationV2
    var menuBarLayout: MenuBarLayoutSnapshot
    var automation: ProfileAutomation?
}

// MARK: - Profile

/// A complete settings profile that can be saved to and restored from disk.
nonisolated struct Profile: Codable, Identifiable {
    let id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var generalSettings: GeneralSettingsSnapshot
    var advancedSettings: AdvancedSettingsSnapshot
    var hotkeys: [String: Data]
    var displayConfigurations: [String: DisplayThawBarConfiguration]
    var globalDisplayConfiguration: DisplayThawBarConfiguration = Defaults.DefaultValue.globalDisplayConfiguration
    var confirmSpacingRelaunch: Bool = Defaults.DefaultValue.confirmSpacingRelaunch
    var unconfirmedSpacingProfileScope: SpacingProfileSaveScope = Defaults.DefaultValue.unconfirmedSpacingProfileScope
    /// Nil in older profiles, which leave the current mode alone when applied.
    var spacingApplyMode: SpacingApplyMode?
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
            spacingApplyMode: spacingApplyMode,
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
        case spacingApplyMode
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
        self.spacingApplyMode = content.spacingApplyMode
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
        ) ?? .defaults

        advancedSettings = try container.decodeIfPresent(
            AdvancedSettingsSnapshot.self,
            forKey: .advancedSettings
        ) ?? .defaults

        hotkeys = try container.decodeIfPresent(
            [String: Data].self,
            forKey: .hotkeys
        ) ?? [:]

        displayConfigurations = try container.decodeIfPresent(
            [String: DisplayThawBarConfiguration].self,
            forKey: .displayConfigurations
        ) ?? Defaults.DefaultValue.displayThawBarConfigurations

        globalDisplayConfiguration = try container.decodeIfPresent(
            DisplayThawBarConfiguration.self,
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

        spacingApplyMode = try container.decodeIfPresent(SpacingApplyMode.self, forKey: .spacingApplyMode)

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

        automation = try container.decodeIfPresent(ProfileAutomation.self, forKey: .automation)
    }
}

// MARK: - ProfileExportEntry

/// A single profile bundled with its metadata for export/import.
/// Preserves display associations that live on the manifest.
nonisolated struct ProfileExportEntry: Codable {
    var profile: Profile
    var associatedDisplayUUID: String?
    var associatedDisplayName: String?
    /// Space associations are exported too, but a key from another Mac will
    /// never match locally, so importing one is harmless rather than useful.
    var associatedSpaceKey: String?
    var associatedSpaceName: String?
    /// The profile's layout switches. Nil in files exported before them.
    var keepsLayoutChanges: Bool?
    var reappliesAtLaunch: Bool?
}

/// Wrapper for exporting multiple profiles as a single file.
nonisolated struct ProfileExportBundle: Codable {
    var version: Int = 1
    var entries: [ProfileExportEntry]
}

// MARK: - Default-backed decoding

private nonisolated extension KeyedDecodingContainer {
    /// Decodes a value when the key is present and falls back to default
    /// when it is absent, which is how every profile snapshot field tolerates
    /// profiles written before the field existed.
    func decode<T: Decodable>(_ key: Key, default defaultValue: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? defaultValue
    }
}
