//
//  ProfileTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Profile metadata")
struct ProfileMetadataTests {
    // MARK: - Initialization Tests

    @Test("Metadata keeps every field it was built with")
    func initialization() {
        let id = UUID()
        let now = Date()
        let metadata = ProfileMetadata(
            id: id,
            name: "Test Profile",
            createdAt: now,
            modifiedAt: now,
            associatedDisplayUUID: "test-uuid",
            associatedDisplayName: "Test Display"
        )

        #expect(metadata.id == id)
        #expect(metadata.name == "Test Profile")
        #expect(metadata.createdAt == now)
        #expect(metadata.modifiedAt == now)
        #expect(metadata.associatedDisplayUUID == "test-uuid")
        #expect(metadata.associatedDisplayName == "Test Display")
    }

    @Test("Metadata built without a display association reports none")
    func initializationWithNilOptionals() {
        let id = UUID()
        let now = Date()
        let metadata = ProfileMetadata(
            id: id,
            name: "Test",
            createdAt: now,
            modifiedAt: now,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )

        #expect(metadata.associatedDisplayUUID == nil)
        #expect(metadata.associatedDisplayName == nil)
    }

    // MARK: - Codable Tests

    @Test("Metadata round-trips through JSON")
    func encodeDecode() throws {
        let original = ProfileMetadata(
            id: UUID(),
            name: "Encoded Profile",
            createdAt: Date(),
            modifiedAt: Date(),
            associatedDisplayUUID: "display-123",
            associatedDisplayName: "My Display"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ProfileMetadata.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.associatedDisplayUUID == original.associatedDisplayUUID)
        #expect(decoded.associatedDisplayName == original.associatedDisplayName)
    }

    // MARK: - Hashable Tests

    @Test("Two metadata values with the same fields hash alike")
    func hashableConformance() {
        let id = UUID()
        let now = Date()
        let metadata1 = ProfileMetadata(id: id, name: "Test", createdAt: now, modifiedAt: now)
        let metadata2 = ProfileMetadata(id: id, name: "Test", createdAt: now, modifiedAt: now)

        #expect(metadata1.hashValue == metadata2.hashValue)
    }

    @Test("Two metadata values built separately get distinct identifiers")
    func uniqueHashForDifferentIds() {
        let now = Date()
        let metadata1 = ProfileMetadata(id: UUID(), name: "Test", createdAt: now, modifiedAt: now)
        let metadata2 = ProfileMetadata(id: UUID(), name: "Test", createdAt: now, modifiedAt: now)

        // Different IDs should typically produce different hashes
        // (not guaranteed but highly likely)
        #expect(metadata1.id != metadata2.id)
    }

    // MARK: - Identifiable Tests

    @Test("Metadata is identified by the identifier it was given")
    func identifiable() {
        let id = UUID()
        let metadata = ProfileMetadata(id: id, name: "Test", createdAt: Date(), modifiedAt: Date())

        #expect(metadata.id == id)
    }
}

@Suite("Menu bar layout snapshot")
struct MenuBarLayoutSnapshotTests {
    // MARK: - Initialization Tests

    @Test("A snapshot keeps every collection it was built with")
    func basicInitialization() {
        let snapshot = MenuBarLayoutSnapshot(
            savedSectionOrder: ["visible": ["app1", "app2"]],
            pinnedHiddenBundleIDs: ["com.hidden.app"],
            pinnedAlwaysHiddenBundleIDs: ["com.always.hidden"],
            customNames: ["app1": "Custom Name"]
        )

        #expect(snapshot.savedSectionOrder["visible"] == ["app1", "app2"])
        #expect(snapshot.pinnedHiddenBundleIDs == ["com.hidden.app"])
        #expect(snapshot.pinnedAlwaysHiddenBundleIDs == ["com.always.hidden"])
        #expect(snapshot.customNames["app1"] == "Custom Name")
    }

    // MARK: - Codable Tests

    @Test("A snapshot round-trips through JSON")
    func encodeDecode() throws {
        let original = MenuBarLayoutSnapshot(
            savedSectionOrder: ["visible": ["a", "b"], "hidden": ["c"]],
            pinnedHiddenBundleIDs: ["com.test.hidden"],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:],
            itemSectionMap: ["item1": "visible"],
            itemOrder: ["visible": ["item1"]]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarLayoutSnapshot.self, from: data)

        #expect(decoded.savedSectionOrder == original.savedSectionOrder)
        #expect(decoded.pinnedHiddenBundleIDs == original.pinnedHiddenBundleIDs)
        #expect(decoded.itemSectionMap == original.itemSectionMap)
        #expect(decoded.itemOrder == original.itemOrder)
    }

    @Test("A snapshot from an older profile format decodes with the new fields absent")
    func decodeWithMissingOptionals() throws {
        // Simulate old profile format without new fields
        let json = """
        {
            "savedSectionOrder": {},
            "pinnedHiddenBundleIDs": [],
            "pinnedAlwaysHiddenBundleIDs": [],
            "customNames": {}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MenuBarLayoutSnapshot.self, from: json)

        #expect(decoded.itemSectionMap == nil)
        #expect(decoded.itemOrder == nil)
        #expect(decoded.newItemsPlacement == nil)
        #expect(decoded.itemHotkeys == nil)
    }

    @Test("A legacy layout falls back to the saved order for item order and sections")
    func legacyLayoutUsesSavedOrderForItemOrderAndSections() throws {
        let json = """
        {
            "savedSectionOrder": {
                "visible": ["com.example.visible:Status"],
                "hidden": ["com.example.hidden:Status"],
                "alwaysHidden": ["com.example.alwaysHidden:Status"]
            },
            "pinnedHiddenBundleIDs": [],
            "pinnedAlwaysHiddenBundleIDs": [],
            "customNames": {}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MenuBarLayoutSnapshot.self, from: json)

        #expect(decoded.resolvedItemOrder == decoded.savedSectionOrder)
        #expect(decoded.resolvedItemSectionMap == [
            "com.example.visible:Status": "visible",
            "com.example.hidden:Status": "hidden",
            "com.example.alwaysHidden:Status": "alwaysHidden",
        ])
    }

    @Test("Per-item hotkeys round-trip through JSON")
    func encodeDecodeItemHotkeys() throws {
        let original = MenuBarLayoutSnapshot(
            savedSectionOrder: [:],
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:],
            itemHotkeys: [
                "com.apple.controlcenter:WiFi": Data([0x01, 0x02]),
                "com.apple.controlcenter:Battery": Data([0x03]),
            ]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarLayoutSnapshot.self, from: data)

        #expect(decoded.itemHotkeys?.count == 2)
        #expect(decoded.itemHotkeys?["com.apple.controlcenter:WiFi"] == Data([0x01, 0x02]))
        #expect(decoded.itemHotkeys?["com.apple.controlcenter:Battery"] == Data([0x03]))
    }

    @Test("A snapshot built from empty collections stays empty")
    func emptyCollections() {
        let snapshot = MenuBarLayoutSnapshot(
            savedSectionOrder: [:],
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:]
        )

        #expect(snapshot.savedSectionOrder.isEmpty)
        #expect(snapshot.pinnedHiddenBundleIDs.isEmpty)
        #expect(snapshot.pinnedAlwaysHiddenBundleIDs.isEmpty)
        #expect(snapshot.customNames.isEmpty)
    }

    @Test("A snapshot spanning all three sections round-trips every collection")
    func multipleSections() throws {
        let snapshot = MenuBarLayoutSnapshot(
            savedSectionOrder: [
                "visible": ["app1", "app2", "app3"],
                "hidden": ["app4", "app5"],
                "alwaysHidden": ["app6"],
            ],
            pinnedHiddenBundleIDs: ["com.app4", "com.app5"],
            pinnedAlwaysHiddenBundleIDs: ["com.app6"],
            customNames: ["app1": "First App", "app2": "Second App"],
            itemSectionMap: [
                "app1": "visible",
                "app4": "hidden",
                "app6": "alwaysHidden",
            ],
            itemOrder: [
                "visible": ["app1", "app2", "app3"],
                "hidden": ["app4", "app5"],
                "alwaysHidden": ["app6"],
            ]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(MenuBarLayoutSnapshot.self, from: data)

        #expect(decoded.savedSectionOrder.count == 3)
        #expect(decoded.pinnedHiddenBundleIDs.count == 2)
        #expect(decoded.pinnedAlwaysHiddenBundleIDs.count == 1)
        #expect(decoded.customNames.count == 2)
        #expect(decoded.itemSectionMap?.count == 3)
        #expect(decoded.itemOrder?.count == 3)
    }
}

// MARK: - Profile Tests

@Suite("Profile")
struct ProfileFullTests {
    /// Swift Testing builds a fresh suite instance per test, so these stand in
    /// for the XCTest `setUp` that rebuilt them before every case.
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Helper Methods

    private func makeTestContent() -> ProfileContent {
        ProfileContent(
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
                savedSectionOrder: [:],
                pinnedHiddenBundleIDs: [],
                pinnedAlwaysHiddenBundleIDs: [],
                customNames: [:]
            )
        )
    }

    // MARK: - Initialization Tests

    /// `id`, `createdAt` and `modifiedAt` are non-optional, so the XCTest
    /// original's `XCTAssertNotNil` on them could never fail. The substantive
    /// form is that the initializer *defaults* the timestamps to now; fresh
    /// identifier generation is covered by ``profileInitGeneratesUniqueId()``.
    @Test("A profile built from content takes its name and defaults its timestamps")
    func profileInitWithContent() {
        let content = makeTestContent()
        let before = Date()
        let profile = Profile(name: "Test Profile", content: content)

        #expect(profile.name == "Test Profile")
        #expect(profile.createdAt >= before)
        #expect(profile.modifiedAt >= before)
    }

    @Test("A profile built with explicit identity keeps it verbatim")
    func profileInitWithCustomDates() {
        let content = makeTestContent()
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_000_000)
        let modified = Date(timeIntervalSince1970: 2_000_000)

        let profile = Profile(
            id: id,
            name: "Custom Dates",
            createdAt: created,
            modifiedAt: modified,
            content: content
        )

        #expect(profile.id == id)
        #expect(profile.createdAt == created)
        #expect(profile.modifiedAt == modified)
    }

    @Test("Each profile gets its own identifier")
    func profileInitGeneratesUniqueId() {
        let content = makeTestContent()
        let profile1 = Profile(name: "Profile 1", content: content)
        let profile2 = Profile(name: "Profile 2", content: content)

        #expect(profile1.id != profile2.id)
    }

    // MARK: - Metadata Property Tests

    @Test("A profile's metadata mirrors its identity fields")
    func metadataProperty() {
        let content = makeTestContent()
        let profile = Profile(name: "Metadata Test", content: content)
        let metadata = profile.metadata

        #expect(metadata.id == profile.id)
        #expect(metadata.name == profile.name)
        #expect(metadata.createdAt == profile.createdAt)
        #expect(metadata.modifiedAt == profile.modifiedAt)
    }

    @Test("A profile's metadata carries no display association")
    func metadataHasNoDisplayAssociation() {
        let content = makeTestContent()
        let profile = Profile(name: "No Display", content: content)
        let metadata = profile.metadata

        // Metadata from Profile doesn't include display association
        #expect(metadata.associatedDisplayUUID == nil)
        #expect(metadata.associatedDisplayName == nil)
    }

    // MARK: - Content Property Tests

    @Test("A profile's content property returns the settings it was built from")
    func contentProperty() {
        let originalContent = makeTestContent()
        let profile = Profile(name: "Content Test", content: originalContent)
        let retrievedContent = profile.content

        #expect(retrievedContent.generalSettings.showIceIcon == originalContent.generalSettings.showIceIcon)
        #expect(
            retrievedContent.advancedSettings.enableAlwaysHiddenSection
                == originalContent.advancedSettings.enableAlwaysHiddenSection
        )
    }

    // MARK: - Encode/Decode Tests

    @Test("A profile round-trips through JSON")
    func encodeDecodeProfile() throws {
        let content = makeTestContent()
        let original = Profile(name: "Encode Test", content: content)

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Profile.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.generalSettings.showIceIcon == original.generalSettings.showIceIcon)
        #expect(
            decoded.advancedSettings.enableAlwaysHiddenSection
                == original.advancedSettings.enableAlwaysHiddenSection
        )
    }

    /// The settings blocks are non-optional, so the XCTest original's
    /// `XCTAssertNotNil` on them could never fail. What the forward-compatible
    /// decoder actually promises is that an absent block is filled from
    /// `Defaults.DefaultValue`, which is what this asserts instead.
    @Test("A profile JSON missing everything but a name decodes with default settings")
    func decodeProfileWithMissingFields() throws {
        // Minimal JSON with only required fields
        let json = """
        {
            "name": "Minimal Profile"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(Profile.self, from: json)

        #expect(decoded.name == "Minimal Profile")
        #expect(decoded.generalSettings.showIceIcon == Defaults.DefaultValue.showIceIcon)
        #expect(
            decoded.advancedSettings.enableAlwaysHiddenSection
                == Defaults.DefaultValue.enableAlwaysHiddenSection
        )
    }

    @Test("An empty profile JSON decodes to the untitled default")
    func decodeProfileWithEmptyJSON() throws {
        let json = "{}".data(using: .utf8)!

        let decoded = try decoder.decode(Profile.self, from: json)

        // Should use defaults
        #expect(decoded.name == String(localized: "Untitled"))
    }

    @Test("Hotkeys and display configurations survive the round trip")
    func decodeProfilePreservesAllFields() throws {
        var content = makeTestContent()
        content.hotkeys = ["toggleHidden": Data([0x01, 0x02])]
        content.displayConfigurations = ["display1": .defaultConfiguration]

        let original = Profile(name: "Full Profile", content: content)

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Profile.self, from: data)

        #expect(decoded.hotkeys.count == 1)
        #expect(decoded.hotkeys["toggleHidden"] != nil)
        #expect(decoded.displayConfigurations.count == 1)
    }

    // MARK: - Identifiable Tests

    /// `Profile` conforms to `Identifiable` with `ID == UUID`: binding `id` to
    /// a typed local is the compile-time half of that claim, and matching the
    /// metadata identifier is the runtime half. (The XCTest original asserted
    /// non-nil on a non-optional `UUID`, which could never fail.)
    @Test("A profile is identifiable by a UUID")
    func profileIsIdentifiable() {
        let content = makeTestContent()
        let profile = Profile(name: "Identifiable", content: content)

        let id: UUID = profile.id

        #expect(id == profile.metadata.id)
    }

    // MARK: - Date Handling Tests

    @Test("Dates survive an ISO8601 round trip to within a second")
    func datesArePreservedOnEncodeDecode() throws {
        let content = makeTestContent()
        let created = Date(timeIntervalSince1970: 1_609_459_200) // 2021-01-01
        let modified = Date(timeIntervalSince1970: 1_640_995_200) // 2022-01-01

        let original = Profile(
            name: "Date Test",
            createdAt: created,
            modifiedAt: modified,
            content: content
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Profile.self, from: data)

        #expect(abs(decoded.createdAt.timeIntervalSince1970 - created.timeIntervalSince1970) < 1.0)
        #expect(abs(decoded.modifiedAt.timeIntervalSince1970 - modified.timeIntervalSince1970) < 1.0)
    }
}

// MARK: - ProfileContent Tests

@Suite("Profile content")
struct ProfileContentTests {
    @Test("Content keeps the settings and collections it was built with")
    func profileContentInitialization() {
        let generalSettings = GeneralSettingsSnapshot(
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

        let advancedSettings = AdvancedSettingsSnapshot(
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

        let content = ProfileContent(
            generalSettings: generalSettings,
            advancedSettings: advancedSettings,
            hotkeys: ["key1": Data()],
            displayConfigurations: ["display1": .defaultConfiguration],
            appearanceConfiguration: .defaultConfiguration,
            menuBarLayout: MenuBarLayoutSnapshot(
                savedSectionOrder: [:],
                pinnedHiddenBundleIDs: [],
                pinnedAlwaysHiddenBundleIDs: [],
                customNames: [:]
            )
        )

        #expect(content.generalSettings.showIceIcon)
        #expect(content.advancedSettings.enableAlwaysHiddenSection)
        #expect(content.hotkeys.count == 1)
        #expect(content.displayConfigurations.count == 1)
    }

    @Test("Content built with empty collections reports them empty")
    func profileContentWithEmptyCollections() {
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
                savedSectionOrder: [:],
                pinnedHiddenBundleIDs: [],
                pinnedAlwaysHiddenBundleIDs: [],
                customNames: [:]
            )
        )

        #expect(content.hotkeys.isEmpty)
        #expect(content.displayConfigurations.isEmpty)
    }
}
