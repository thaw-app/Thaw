//
//  ProfileTestFixtures.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import Thaw

// MARK: - Snapshot fixtures

/// The general settings block every profile fixture shares.
///
/// The values are arbitrary but load-bearing: several round-trip tests assert
/// them back out (`rehideInterval == 15`, `showOnClick`, ...), so change them
/// only together with those assertions.
func makeTestGeneralSettings() -> GeneralSettingsSnapshot {
    GeneralSettingsSnapshot(
        showIceIcon: true,
        iceIcon: .defaultIceIcon,
        lastCustomIceIcon: nil,
        customIceIconIsTemplate: true,
        useIceBar: false,
        useIceBarOnlyOnNotchedDisplay: false,
        iceBarLocation: .dynamic,
        iceBarLocationOnHotkey: false,
        showOnClick: true,
        showOnDoubleClick: false,
        showOnHover: false,
        showOnScroll: false,
        autoRehide: true,
        rehideStrategyRawValue: 0,
        rehideInterval: 15
    )
}

/// The advanced settings block every profile fixture shares. Same caveat as
/// ``makeTestGeneralSettings()``: tests assert `showOnHoverDelay == 0.2`,
/// `tooltipDelay == 1.0` and friends.
func makeTestAdvancedSettings() -> AdvancedSettingsSnapshot {
    AdvancedSettingsSnapshot(
        enableAlwaysHiddenSection: true,
        showAllSectionsOnUserDrag: true,
        sectionDividerStyle: 0,
        hideApplicationMenus: false,
        enableSecondaryContextMenu: true,
        enableSecondaryContextMenuQuit: false,
        showOnHoverDelay: 0.2,
        tooltipDelay: 1.0,
        showMenuBarTooltips: true,
        iconRefreshInterval: 3.0,
        enableDiagnosticLogging: false,
        useDoubleClickToShowAlwaysHiddenSection: false,
        useOptionClickToShowAlwaysHiddenSection: false,
        useLCSSortingOnNotchedDisplays: false,
        enableMenuBarItemOverflow: false,
        searchSectionOrder: ["visible", "hidden", "alwaysHidden"],
        searchIncludeVisible: true,
        searchIncludeHidden: true,
        searchIncludeAlwaysHidden: true
    )
}

/// Builds the `ProfileContent` the profile fixtures share, with the
/// collection-valued fields parameterized for the tests that need them
/// populated.
func makeTestProfileContent(
    hotkeys: [String: Data] = [:],
    displayConfigurations: [String: DisplayIceBarConfiguration] = [:],
    savedSectionOrder: [String: [String]] = [:]
) -> ProfileContent {
    ProfileContent(
        generalSettings: makeTestGeneralSettings(),
        advancedSettings: makeTestAdvancedSettings(),
        hotkeys: hotkeys,
        displayConfigurations: displayConfigurations,
        appearanceConfiguration: .defaultConfiguration,
        menuBarLayout: MenuBarLayoutSnapshot(
            savedSectionOrder: savedSectionOrder,
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:]
        )
    )
}

// MARK: - Profile fixtures

/// Builds the standard test profile that was previously duplicated across the
/// `ProfileManager` suites.
func makeProfile(
    named name: String = "Test Profile",
    savedSectionOrder: [String: [String]] = [:],
    displayConfigurations: [String: DisplayIceBarConfiguration] = [:]
) -> Profile {
    Profile(
        name: name,
        content: makeTestProfileContent(
            displayConfigurations: displayConfigurations,
            savedSectionOrder: savedSectionOrder
        )
    )
}

// MARK: - Manifest seeding

/// Writes each profile's JSON plus a `profiles.json` manifest, so a freshly
/// constructed `ProfileManager` loads them the way it would in production.
func seedManifest(with profiles: [Profile], into directory: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    for profile in profiles {
        let data = try encoder.encode(profile)
        try data.write(
            to: directory.appendingPathComponent("\(profile.id.uuidString).json"),
            options: .atomic
        )
    }

    let metadata = profiles.map {
        ProfileMetadata(id: $0.id, name: $0.name, createdAt: $0.createdAt, modifiedAt: $0.modifiedAt)
    }
    let manifestData = try encoder.encode(metadata)
    try manifestData.write(
        to: directory.appendingPathComponent("profiles.json"),
        options: .atomic
    )
}
