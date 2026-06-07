//
//  ProfileManagerUpdateRearmIntegrationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// End-to-end regression lock for the update-re-arms-cache wiring.
///
/// Drives the real ProfileManager.updateProfileLayout path against an injected
/// temporary profiles directory and a standalone MenuBarItemManager: it loads
/// the profile from disk, captures the live layout, writes the update back, and
/// re-arms the in-memory cache. This is the integration the gate test and the
/// MenuBarItemManager cache test could not reach on their own. It fails if the
/// rearm wiring is removed from updateProfileLayout.
@MainActor
final class ProfileManagerUpdateRearmIntegrationTests: XCTestCase {
    private let savedSectionOrderKey = "MenuBarItemManager.savedSectionOrder"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: savedSectionOrderKey)
        super.tearDown()
    }

    /// A profile is active with an item in Always-Hidden, the user moves it to
    /// Hidden (updating the live savedSectionOrder), then updates the active
    /// profile's layout. The item manager's cached spec must follow to Hidden,
    /// so a later late-arrival re-sort no longer drags the item back into
    /// Always-Hidden. Without the re-arm wiring the cache stays on the
    /// Always-Hidden spec and this fails.
    func testUpdatingActiveProfileLayoutRearmsCacheEndToEnd() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let profileManager = ProfileManager(profilesDirectory: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let itemManager = MenuBarItemManager()
        let uid = "com.example.app:Item-0"

        // A profile exists on disk and is the active one.
        let profile = makeProfile(savedSectionOrder: ["alwaysHidden": [uid]])
        try writeProfile(profile, into: tmp)
        profileManager.activeProfileID = profile.id

        // Cache armed as if the profile were applied: item in Always-Hidden.
        itemManager.rearmActiveProfileLayout(
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: ["alwaysHidden": [uid]],
            itemSectionMap: [uid: "alwaysHidden"],
            itemOrder: ["alwaysHidden": [uid]]
        )
        XCTAssertEqual(
            itemManager.activeProfileLayout?.sectionOrder,
            ["alwaysHidden": [uid]],
            "Precondition: cache reflects the applied (Always-Hidden) spec"
        )

        // The user dragged the item to Hidden: the live layout is now B.
        UserDefaults.standard.set(["hidden": [uid]], forKey: savedSectionOrderKey)

        // The user updates the active profile's layout.
        try profileManager.updateProfileLayout(id: profile.id, itemManager: itemManager)

        // The cache now reflects Hidden, so the next late-arrival re-sort
        // targets the updated layout instead of reverting to Always-Hidden.
        XCTAssertEqual(
            itemManager.activeProfileLayout?.sectionOrder,
            ["hidden": [uid]],
            "Updating the active profile must re-arm the cache to the new layout"
        )
    }

    /// Updating a profile that is not the active one must not touch the cache,
    /// even end-to-end: the disk write happens but the in-memory spec is left
    /// pointing at the active profile's layout.
    func testUpdatingInactiveProfileDoesNotRearmCache() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let profileManager = ProfileManager(profilesDirectory: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let itemManager = MenuBarItemManager()
        let uid = "com.example.app:Item-0"

        let inactiveProfile = makeProfile(savedSectionOrder: ["alwaysHidden": [uid]])
        try writeProfile(inactiveProfile, into: tmp)
        // A different profile is the active one.
        profileManager.activeProfileID = UUID()

        itemManager.rearmActiveProfileLayout(
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: ["alwaysHidden": [uid]],
            itemSectionMap: [uid: "alwaysHidden"],
            itemOrder: ["alwaysHidden": [uid]]
        )

        UserDefaults.standard.set(["hidden": [uid]], forKey: savedSectionOrderKey)
        try profileManager.updateProfileLayout(id: inactiveProfile.id, itemManager: itemManager)

        XCTAssertEqual(
            itemManager.activeProfileLayout?.sectionOrder,
            ["alwaysHidden": [uid]],
            "Updating a non-active profile must leave the active cache untouched"
        )
    }

    // MARK: - Helpers

    private func makeProfile(savedSectionOrder: [String: [String]]) -> Profile {
        let content = ProfileContent(
            generalSettings: GeneralSettingsSnapshot(
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
            ),
            advancedSettings: AdvancedSettingsSnapshot(
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
            ),
            hotkeys: [:],
            displayConfigurations: [:],
            appearanceConfiguration: .defaultConfiguration,
            menuBarLayout: MenuBarLayoutSnapshot(
                savedSectionOrder: savedSectionOrder,
                pinnedHiddenBundleIDs: [],
                pinnedAlwaysHiddenBundleIDs: [],
                customNames: [:]
            )
        )
        return Profile(name: "Integration Test", content: content)
    }

    private func writeProfile(_ profile: Profile, into directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(
            to: directory.appendingPathComponent("\(profile.id.uuidString).json"),
            options: .atomic
        )
    }
}
