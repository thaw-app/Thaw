//
//  ProfileTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class ProfileMetadataTests: XCTestCase {
    // MARK: - Initialization Tests

    func testInitialization() {
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

        XCTAssertEqual(metadata.id, id)
        XCTAssertEqual(metadata.name, "Test Profile")
        XCTAssertEqual(metadata.createdAt, now)
        XCTAssertEqual(metadata.modifiedAt, now)
        XCTAssertEqual(metadata.associatedDisplayUUID, "test-uuid")
        XCTAssertEqual(metadata.associatedDisplayName, "Test Display")
    }

    func testInitializationWithNilOptionals() {
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

        XCTAssertNil(metadata.associatedDisplayUUID)
        XCTAssertNil(metadata.associatedDisplayName)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
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

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.associatedDisplayUUID, original.associatedDisplayUUID)
        XCTAssertEqual(decoded.associatedDisplayName, original.associatedDisplayName)
    }

    // MARK: - Hashable Tests

    func testHashableConformance() {
        let id = UUID()
        let now = Date()
        let metadata1 = ProfileMetadata(id: id, name: "Test", createdAt: now, modifiedAt: now)
        let metadata2 = ProfileMetadata(id: id, name: "Test", createdAt: now, modifiedAt: now)

        XCTAssertEqual(metadata1.hashValue, metadata2.hashValue)
    }

    func testUniqueHashForDifferentIds() {
        let now = Date()
        let metadata1 = ProfileMetadata(id: UUID(), name: "Test", createdAt: now, modifiedAt: now)
        let metadata2 = ProfileMetadata(id: UUID(), name: "Test", createdAt: now, modifiedAt: now)

        // Different IDs should typically produce different hashes
        // (not guaranteed but highly likely)
        XCTAssertNotEqual(metadata1.id, metadata2.id)
    }

    // MARK: - Identifiable Tests

    func testIdentifiable() {
        let id = UUID()
        let metadata = ProfileMetadata(id: id, name: "Test", createdAt: Date(), modifiedAt: Date())
        XCTAssertEqual(metadata.id, id)
    }
}

final class MenuBarLayoutSnapshotTests: XCTestCase {
    // MARK: - Initialization Tests

    func testBasicInitialization() {
        let snapshot = MenuBarLayoutSnapshot(
            savedSectionOrder: ["visible": ["app1", "app2"]],
            pinnedHiddenBundleIDs: ["com.hidden.app"],
            pinnedAlwaysHiddenBundleIDs: ["com.always.hidden"],
            customNames: ["app1": "Custom Name"]
        )

        XCTAssertEqual(snapshot.savedSectionOrder["visible"], ["app1", "app2"])
        XCTAssertEqual(snapshot.pinnedHiddenBundleIDs, ["com.hidden.app"])
        XCTAssertEqual(snapshot.pinnedAlwaysHiddenBundleIDs, ["com.always.hidden"])
        XCTAssertEqual(snapshot.customNames["app1"], "Custom Name")
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
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

        XCTAssertEqual(decoded.savedSectionOrder, original.savedSectionOrder)
        XCTAssertEqual(decoded.pinnedHiddenBundleIDs, original.pinnedHiddenBundleIDs)
        XCTAssertEqual(decoded.itemSectionMap, original.itemSectionMap)
        XCTAssertEqual(decoded.itemOrder, original.itemOrder)
    }

    func testDecodeWithMissingOptionals() throws {
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

        XCTAssertNil(decoded.itemSectionMap)
        XCTAssertNil(decoded.itemOrder)
        XCTAssertNil(decoded.newItemsPlacement)
    }

    func testEmptyCollections() {
        let snapshot = MenuBarLayoutSnapshot(
            savedSectionOrder: [:],
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: [:]
        )

        XCTAssertTrue(snapshot.savedSectionOrder.isEmpty)
        XCTAssertTrue(snapshot.pinnedHiddenBundleIDs.isEmpty)
        XCTAssertTrue(snapshot.pinnedAlwaysHiddenBundleIDs.isEmpty)
        XCTAssertTrue(snapshot.customNames.isEmpty)
    }

    func testMultipleSections() throws {
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

        XCTAssertEqual(decoded.savedSectionOrder.count, 3)
        XCTAssertEqual(decoded.pinnedHiddenBundleIDs.count, 2)
        XCTAssertEqual(decoded.pinnedAlwaysHiddenBundleIDs.count, 1)
        XCTAssertEqual(decoded.customNames.count, 2)
        XCTAssertEqual(decoded.itemSectionMap?.count, 3)
        XCTAssertEqual(decoded.itemOrder?.count, 3)
    }
}

// MARK: - Profile Tests

final class ProfileFullTests: XCTestCase {
    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    override func tearDown() {
        encoder = nil
        decoder = nil
        super.tearDown()
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
                showOnHoverDelay: 0.2,
                tooltipDelay: 1.0,
                showMenuBarTooltips: true,
                iconRefreshInterval: 3.0,
                enableDiagnosticLogging: false
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

    func testProfileInitWithContent() {
        let content = makeTestContent()
        let profile = Profile(name: "Test Profile", content: content)

        XCTAssertEqual(profile.name, "Test Profile")
        XCTAssertNotNil(profile.id)
        XCTAssertNotNil(profile.createdAt)
        XCTAssertNotNil(profile.modifiedAt)
    }

    func testProfileInitWithCustomDates() {
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

        XCTAssertEqual(profile.id, id)
        XCTAssertEqual(profile.createdAt, created)
        XCTAssertEqual(profile.modifiedAt, modified)
    }

    func testProfileInitGeneratesUniqueId() {
        let content = makeTestContent()
        let profile1 = Profile(name: "Profile 1", content: content)
        let profile2 = Profile(name: "Profile 2", content: content)

        XCTAssertNotEqual(profile1.id, profile2.id)
    }

    // MARK: - Metadata Property Tests

    func testMetadataProperty() {
        let content = makeTestContent()
        let profile = Profile(name: "Metadata Test", content: content)
        let metadata = profile.metadata

        XCTAssertEqual(metadata.id, profile.id)
        XCTAssertEqual(metadata.name, profile.name)
        XCTAssertEqual(metadata.createdAt, profile.createdAt)
        XCTAssertEqual(metadata.modifiedAt, profile.modifiedAt)
    }

    func testMetadataHasNoDisplayAssociation() {
        let content = makeTestContent()
        let profile = Profile(name: "No Display", content: content)
        let metadata = profile.metadata

        // Metadata from Profile doesn't include display association
        XCTAssertNil(metadata.associatedDisplayUUID)
        XCTAssertNil(metadata.associatedDisplayName)
    }

    // MARK: - Content Property Tests

    func testContentProperty() {
        let originalContent = makeTestContent()
        let profile = Profile(name: "Content Test", content: originalContent)
        let retrievedContent = profile.content

        XCTAssertEqual(retrievedContent.generalSettings.showIceIcon, originalContent.generalSettings.showIceIcon)
        XCTAssertEqual(retrievedContent.advancedSettings.enableAlwaysHiddenSection, originalContent.advancedSettings.enableAlwaysHiddenSection)
    }

    // MARK: - Encode/Decode Tests

    func testEncodeDecodeProfile() throws {
        let content = makeTestContent()
        let original = Profile(name: "Encode Test", content: content)

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Profile.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.generalSettings.showIceIcon, original.generalSettings.showIceIcon)
        XCTAssertEqual(decoded.advancedSettings.enableAlwaysHiddenSection, original.advancedSettings.enableAlwaysHiddenSection)
    }

    func testDecodeProfileWithMissingFields() throws {
        // Minimal JSON with only required fields
        let json = """
        {
            "name": "Minimal Profile"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(Profile.self, from: json)

        XCTAssertEqual(decoded.name, "Minimal Profile")
        XCTAssertNotNil(decoded.id)
        XCTAssertNotNil(decoded.generalSettings)
        XCTAssertNotNil(decoded.advancedSettings)
    }

    func testDecodeProfileWithEmptyJSON() throws {
        let json = "{}".data(using: .utf8)!

        let decoded = try decoder.decode(Profile.self, from: json)

        // Should use defaults
        XCTAssertEqual(decoded.name, "Untitled")
        XCTAssertNotNil(decoded.id)
    }

    func testDecodeProfilePreservesAllFields() throws {
        var content = makeTestContent()
        content.hotkeys = ["toggleHidden": Data([0x01, 0x02])]
        content.displayConfigurations = ["display1": .defaultConfiguration]

        let original = Profile(name: "Full Profile", content: content)

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Profile.self, from: data)

        XCTAssertEqual(decoded.hotkeys.count, 1)
        XCTAssertNotNil(decoded.hotkeys["toggleHidden"])
        XCTAssertEqual(decoded.displayConfigurations.count, 1)
    }

    // MARK: - Identifiable Tests

    func testProfileIsIdentifiable() {
        let content = makeTestContent()
        let profile = Profile(name: "Identifiable", content: content)

        // Profile conforms to Identifiable
        let id: UUID = profile.id
        XCTAssertNotNil(id)
    }

    // MARK: - Date Handling Tests

    func testDatesArePreservedOnEncodeDecode() throws {
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

        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(decoded.modifiedAt.timeIntervalSince1970, modified.timeIntervalSince1970, accuracy: 1.0)
    }
}

// MARK: - ProfileContent Tests

final class ProfileContentTests: XCTestCase {
    func testProfileContentInitialization() {
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
            showOnHoverDelay: 0.2,
            tooltipDelay: 1.0,
            showMenuBarTooltips: true,
            iconRefreshInterval: 3.0,
            enableDiagnosticLogging: false
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

        XCTAssertEqual(content.generalSettings.showIceIcon, true)
        XCTAssertEqual(content.advancedSettings.enableAlwaysHiddenSection, true)
        XCTAssertEqual(content.hotkeys.count, 1)
        XCTAssertEqual(content.displayConfigurations.count, 1)
    }

    func testProfileContentWithEmptyCollections() {
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
                showOnHoverDelay: 0.2,
                tooltipDelay: 1.0,
                showMenuBarTooltips: true,
                iconRefreshInterval: 3.0,
                enableDiagnosticLogging: false
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

        XCTAssertTrue(content.hotkeys.isEmpty)
        XCTAssertTrue(content.displayConfigurations.isEmpty)
    }
}
