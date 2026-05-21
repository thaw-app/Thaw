//
//  ProfileExportBundleTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class ProfileExportBundleTests: XCTestCase {
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

    private func makeTestProfile(name: String = "Test Profile") -> Profile {
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
                enableMenuBarItemOverflow: false
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
        return Profile(name: name, content: content)
    }

    // MARK: - ProfileExportBundle Tests

    func testEmptyBundleEncodeDecode() throws {
        let bundle = ProfileExportBundle(entries: [])

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertTrue(decoded.entries.isEmpty)
    }

    func testVersionFieldDefaultsToOne() {
        let bundle = ProfileExportBundle(entries: [])
        XCTAssertEqual(bundle.version, 1)
    }

    func testSingleEntryEncodeDecode() throws {
        let profile = makeTestProfile(name: "Single Profile")
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )
        let bundle = ProfileExportBundle(entries: [entry])

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries[0].profile.name, "Single Profile")
        XCTAssertNil(decoded.entries[0].associatedDisplayUUID)
        XCTAssertNil(decoded.entries[0].associatedDisplayName)
    }

    func testMultipleEntriesEncodeDecode() throws {
        let profile1 = makeTestProfile(name: "Profile One")
        let profile2 = makeTestProfile(name: "Profile Two")
        let profile3 = makeTestProfile(name: "Profile Three")

        let entries = [
            ProfileExportEntry(profile: profile1, associatedDisplayUUID: nil, associatedDisplayName: nil),
            ProfileExportEntry(profile: profile2, associatedDisplayUUID: "uuid-2", associatedDisplayName: "Display 2"),
            ProfileExportEntry(profile: profile3, associatedDisplayUUID: "uuid-3", associatedDisplayName: nil),
        ]
        let bundle = ProfileExportBundle(entries: entries)

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        XCTAssertEqual(decoded.entries.count, 3)
        XCTAssertEqual(decoded.entries[0].profile.name, "Profile One")
        XCTAssertEqual(decoded.entries[1].profile.name, "Profile Two")
        XCTAssertEqual(decoded.entries[2].profile.name, "Profile Three")
    }

    func testEntryWithDisplayAssociation() throws {
        let profile = makeTestProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: "12345-ABCDE-67890",
            associatedDisplayName: "Built-in Retina Display"
        )
        let bundle = ProfileExportBundle(entries: [entry])

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        XCTAssertEqual(decoded.entries[0].associatedDisplayUUID, "12345-ABCDE-67890")
        XCTAssertEqual(decoded.entries[0].associatedDisplayName, "Built-in Retina Display")
    }

    func testEntryWithoutDisplayAssociation() throws {
        let profile = makeTestProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )
        let bundle = ProfileExportBundle(entries: [entry])

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        XCTAssertNil(decoded.entries[0].associatedDisplayUUID)
        XCTAssertNil(decoded.entries[0].associatedDisplayName)
    }

    func testEntryWithUUIDButNoName() throws {
        let profile = makeTestProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: "some-uuid",
            associatedDisplayName: nil
        )
        let bundle = ProfileExportBundle(entries: [entry])

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        XCTAssertEqual(decoded.entries[0].associatedDisplayUUID, "some-uuid")
        XCTAssertNil(decoded.entries[0].associatedDisplayName)
    }

    // MARK: - ProfileExportEntry Tests

    func testExportEntryPreservesProfileId() throws {
        let profile = makeTestProfile()
        let originalId = profile.id
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(ProfileExportEntry.self, from: data)

        XCTAssertEqual(decoded.profile.id, originalId)
    }

    func testExportEntryPreservesProfileDates() throws {
        let profile = makeTestProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(ProfileExportEntry.self, from: data)

        // Dates should be equal within a second (ISO8601 encoding)
        XCTAssertEqual(
            decoded.profile.createdAt.timeIntervalSince1970,
            profile.createdAt.timeIntervalSince1970,
            accuracy: 1.0
        )
        XCTAssertEqual(
            decoded.profile.modifiedAt.timeIntervalSince1970,
            profile.modifiedAt.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func testExportEntryPreservesGeneralSettings() throws {
        let profile = makeTestProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(ProfileExportEntry.self, from: data)

        XCTAssertEqual(decoded.profile.generalSettings.showIceIcon, true)
        XCTAssertEqual(decoded.profile.generalSettings.autoRehide, true)
        XCTAssertEqual(decoded.profile.generalSettings.rehideInterval, 15)
    }

    func testExportEntryPreservesAdvancedSettings() throws {
        let profile = makeTestProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(ProfileExportEntry.self, from: data)

        XCTAssertEqual(decoded.profile.advancedSettings.enableAlwaysHiddenSection, true)
        XCTAssertEqual(decoded.profile.advancedSettings.showOnHoverDelay, 0.2)
        XCTAssertEqual(decoded.profile.advancedSettings.tooltipDelay, 1.0)
    }

    // MARK: - JSON Structure Tests

    func testBundleJSONContainsVersionField() throws {
        let bundle = ProfileExportBundle(entries: [])
        let data = try encoder.encode(bundle)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["version"])
        XCTAssertEqual(json?["version"] as? Int, 1)
    }

    func testBundleJSONContainsEntriesArray() throws {
        let bundle = ProfileExportBundle(entries: [])
        let data = try encoder.encode(bundle)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["entries"])
        XCTAssertTrue(json?["entries"] is [Any])
    }
}
