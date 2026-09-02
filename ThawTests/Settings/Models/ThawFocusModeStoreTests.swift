//
//  ThawFocusModeStoreTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Exercises the Focus Filter profile resolution against a real manifest
/// file written into the test host's Application Support directory.
///
/// ``ThawFocusModeStore`` caches the parsed manifest against its
/// modification date, so these tests set explicit modification dates to
/// walk the cache through its hit and miss paths. The static cache and the
/// Defaults facade are process-wide, hence `.serialized`.
@Suite("Thaw Focus mode store")
@MainActor
struct ThawFocusModeStoreTests {
    private let profilesDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Thaw/Profiles", isDirectory: true)

    /// Writes a manifest with the given profiles and stamps an explicit
    /// modification date so the store's cache can be driven precisely.
    private func writeManifest(_ profiles: [ProfileMetadata], modifiedAt: Date) throws {
        try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profiles)
        try data.write(to: ThawFocusModeStore.manifestURL!, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: ThawFocusModeStore.manifestURL!.path
        )
    }

    private func removeManifest() {
        try? FileManager.default.removeItem(at: profilesDirectory)
    }

    private func metadata(id: UUID, name: String) -> ProfileMetadata {
        ProfileMetadata(
            id: id,
            name: name,
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            associatedDisplayUUID: nil,
            associatedDisplayName: nil,
            associatedSpaceKey: nil,
            associatedSpaceName: nil
        )
    }

    @Test("The manifest URL points at Thaw/Profiles/profiles.json")
    func manifestURLShape() {
        let url = ThawFocusModeStore.manifestURL
        #expect(url?.lastPathComponent == "profiles.json")
        #expect(url?.path.hasSuffix("Thaw/Profiles/profiles.json") == true)
    }

    @Test("No requested profile id means no active mode")
    func noRequestMeansNoMode() throws {
        try withScratchDefaults { _ in
            Defaults.removeObject(forKey: .focusFilterRequestedProfileID)
            #expect(ThawFocusModeStore.activeMode == nil)
        }
    }

    @Test("An empty requested id is treated as no request")
    func emptyRequestIsIgnored() throws {
        try withScratchDefaults { _ in
            Defaults.set("", forKey: .focusFilterRequestedProfileID)
            #expect(ThawFocusModeStore.activeMode == nil)
        }
    }

    @Test("A missing manifest falls back to the raw profile id")
    func missingManifestPassesIdThrough() throws {
        try withScratchDefaults { _ in
            removeManifest()
            Defaults.set("work-profile-id", forKey: .focusFilterRequestedProfileID)
            #expect(ThawFocusModeStore.activeMode == "work-profile-id")
        }
    }

    @Test("A manifest entry resolves the id to its profile name")
    func manifestResolvesTheName() throws {
        try withScratchDefaults { _ in
            removeManifest()
            let id = UUID()
            try writeManifest(
                [metadata(id: id, name: "Work Layout")],
                modifiedAt: Date(timeIntervalSince1970: 1000)
            )
            Defaults.set(id.uuidString, forKey: .focusFilterRequestedProfileID)

            #expect(ThawFocusModeStore.activeMode == "Work Layout")
        }
    }

    @Test("An id absent from the manifest passes through unchanged")
    func unknownIdPassesThrough() throws {
        try withScratchDefaults { _ in
            removeManifest()
            try writeManifest(
                [metadata(id: UUID(), name: "Work Layout")],
                modifiedAt: Date(timeIntervalSince1970: 1000)
            )
            Defaults.set(UUID().uuidString, forKey: .focusFilterRequestedProfileID)

            let active = ThawFocusModeStore.activeMode
            #expect(active != nil)
            #expect(active == Defaults.string(forKey: .focusFilterRequestedProfileID))
        }
    }

    @Test("The manifest is re-read only when its modification date changes")
    func cacheHonorsTheModificationDate() throws {
        try withScratchDefaults { _ in
            removeManifest()
            let id = UUID()
            let originalDate = Date(timeIntervalSince1970: 2000)
            try writeManifest(
                [metadata(id: id, name: "Original Name")],
                modifiedAt: originalDate
            )
            Defaults.set(id.uuidString, forKey: .focusFilterRequestedProfileID)
            #expect(ThawFocusModeStore.activeMode == "Original Name")

            // Rewrite the content but restore the old modification date:
            // the store must keep answering from its cache.
            try writeManifest(
                [metadata(id: id, name: "Renamed While Mtime Held")],
                modifiedAt: originalDate
            )
            #expect(ThawFocusModeStore.activeMode == "Original Name")

            // A new modification date invalidates the cache.
            try writeManifest(
                [metadata(id: id, name: "Renamed For Real")],
                modifiedAt: Date(timeIntervalSince1970: 3000)
            )
            #expect(ThawFocusModeStore.activeMode == "Renamed For Real")
        }
    }

    @Test("A corrupted manifest yields the raw id rather than crashing")
    func corruptedManifestPassesIdThrough() throws {
        try withScratchDefaults { _ in
            removeManifest()
            try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
            let url = ThawFocusModeStore.manifestURL!
            try Data("not json at all".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 5000)],
                ofItemAtPath: url.path
            )
            Defaults.set("some-profile-id", forKey: .focusFilterRequestedProfileID)

            #expect(ThawFocusModeStore.activeMode == "some-profile-id")
        }
    }
}
