//
//  ProfileExportBundleTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Profile export bundle")
struct ProfileExportBundleTests {
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

    // MARK: - ProfileExportBundle Tests

    @Test("An empty bundle round-trips with its version intact")
    func emptyBundleEncodeDecode() throws {
        let bundle = ProfileExportBundle(entries: [])

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.entries.isEmpty)
    }

    @Test("A new bundle is stamped version 1")
    func versionFieldDefaultsToOne() {
        let bundle = ProfileExportBundle(entries: [])

        #expect(bundle.version == 1)
    }

    @Test("A single-entry bundle round-trips its profile")
    func singleEntryEncodeDecode() throws {
        let profile = makeProfile(named: "Single Profile")
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )
        let bundle = ProfileExportBundle(entries: [entry])

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        #expect(decoded.entries.count == 1)
        #expect(decoded.entries[0].profile.name == "Single Profile")
        #expect(decoded.entries[0].associatedDisplayUUID == nil)
        #expect(decoded.entries[0].associatedDisplayName == nil)
    }

    @Test("A multi-entry bundle round-trips every profile in order")
    func multipleEntriesEncodeDecode() throws {
        let profile1 = makeProfile(named: "Profile One")
        let profile2 = makeProfile(named: "Profile Two")
        let profile3 = makeProfile(named: "Profile Three")

        let entries = [
            ProfileExportEntry(profile: profile1, associatedDisplayUUID: nil, associatedDisplayName: nil),
            ProfileExportEntry(profile: profile2, associatedDisplayUUID: "uuid-2", associatedDisplayName: "Display 2"),
            ProfileExportEntry(profile: profile3, associatedDisplayUUID: "uuid-3", associatedDisplayName: nil),
        ]
        let bundle = ProfileExportBundle(entries: entries)

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        #expect(decoded.entries.count == 3)
        #expect(decoded.entries[0].profile.name == "Profile One")
        #expect(decoded.entries[1].profile.name == "Profile Two")
        #expect(decoded.entries[2].profile.name == "Profile Three")
    }

    @Test("An entry's display association survives the round trip")
    func entryWithDisplayAssociation() throws {
        let profile = makeProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: "12345-ABCDE-67890",
            associatedDisplayName: "Built-in Retina Display"
        )
        let bundle = ProfileExportBundle(entries: [entry])

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        #expect(decoded.entries[0].associatedDisplayUUID == "12345-ABCDE-67890")
        #expect(decoded.entries[0].associatedDisplayName == "Built-in Retina Display")
    }

    @Test("An entry with no display association decodes back to nil")
    func entryWithoutDisplayAssociation() throws {
        let profile = makeProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )
        let bundle = ProfileExportBundle(entries: [entry])

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        #expect(decoded.entries[0].associatedDisplayUUID == nil)
        #expect(decoded.entries[0].associatedDisplayName == nil)
    }

    @Test("An entry can carry a display UUID with no display name")
    func entryWithUUIDButNoName() throws {
        let profile = makeProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: "some-uuid",
            associatedDisplayName: nil
        )
        let bundle = ProfileExportBundle(entries: [entry])

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ProfileExportBundle.self, from: data)

        #expect(decoded.entries[0].associatedDisplayUUID == "some-uuid")
        #expect(decoded.entries[0].associatedDisplayName == nil)
    }

    // MARK: - ProfileExportEntry Tests

    @Test("An entry preserves its profile's identifier")
    func exportEntryPreservesProfileId() throws {
        let profile = makeProfile()
        let originalId = profile.id
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(ProfileExportEntry.self, from: data)

        #expect(decoded.profile.id == originalId)
    }

    @Test("An entry preserves its profile's dates")
    func exportEntryPreservesProfileDates() throws {
        let profile = makeProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(ProfileExportEntry.self, from: data)

        // Dates should be equal within a second (ISO8601 encoding)
        #expect(
            abs(decoded.profile.createdAt.timeIntervalSince1970 - profile.createdAt.timeIntervalSince1970) < 1.0
        )
        #expect(
            abs(decoded.profile.modifiedAt.timeIntervalSince1970 - profile.modifiedAt.timeIntervalSince1970) < 1.0
        )
    }

    @Test("An entry preserves its profile's general settings")
    func exportEntryPreservesGeneralSettings() throws {
        let profile = makeProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(ProfileExportEntry.self, from: data)

        #expect(decoded.profile.generalSettings.showIceIcon)
        #expect(decoded.profile.generalSettings.autoRehide)
        #expect(decoded.profile.generalSettings.rehideInterval == 15)
    }

    @Test("An entry preserves its profile's advanced settings")
    func exportEntryPreservesAdvancedSettings() throws {
        let profile = makeProfile()
        let entry = ProfileExportEntry(
            profile: profile,
            associatedDisplayUUID: nil,
            associatedDisplayName: nil
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(ProfileExportEntry.self, from: data)

        #expect(decoded.profile.advancedSettings.enableAlwaysHiddenSection)
        #expect(decoded.profile.advancedSettings.showOnHoverDelay == 0.2)
        #expect(decoded.profile.advancedSettings.tooltipDelay == 1.0)
    }

    // MARK: - JSON Structure Tests

    @Test("The encoded bundle carries a version field set to 1")
    func bundleJSONContainsVersionField() throws {
        let bundle = ProfileExportBundle(entries: [])
        let data = try encoder.encode(bundle)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["version"] != nil)
        #expect(json?["version"] as? Int == 1)
    }

    @Test("The encoded bundle carries an entries array")
    func bundleJSONContainsEntriesArray() throws {
        let bundle = ProfileExportBundle(entries: [])
        let data = try encoder.encode(bundle)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["entries"] != nil)
        #expect(json?["entries"] is [Any])
    }
}
