//
//  ProfileSpaceAssociationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Pins the Space half of profile auto-switching: the manifest fields, the
/// one-profile-per-Space rule, the reverse lookup, and the export/import
/// round trip. The live switch itself needs a window server and an
/// AppState, so it is out of reach here; everything below runs against a
/// real ProfileManager pointed at a per-test temporary directory, so the
/// on-disk manifest is exercised for real and reloaded where it matters.
@MainActor
@Suite("Profile Space association", .serialized)
struct ProfileSpaceAssociationTests {
    // MARK: Persistence

    @Test("A Space association persists in the manifest with its label")
    func spaceAssociationPersists() throws {
        try withManager(seeding: ["Writing"]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)

            manager.setAssociatedSpace(key: "SPACE-UUID-A", spaceName: "Desktop 2", forProfileID: id)

            #expect(manager.profiles.first?.associatedSpaceKey == "SPACE-UUID-A")
            #expect(manager.profiles.first?.associatedSpaceName == "Desktop 2")

            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.first?.associatedSpaceKey == "SPACE-UUID-A")
            #expect(reloaded.profiles.first?.associatedSpaceName == "Desktop 2")
        }
    }

    @Test("Passing nil clears the Space association and its cached label")
    func spaceAssociationCanBeCleared() throws {
        try withManager(seeding: ["Writing"]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", spaceName: "Desktop 2", forProfileID: id)

            manager.setAssociatedSpace(key: nil, forProfileID: id)

            #expect(manager.profiles.first?.associatedSpaceKey == nil)
            #expect(manager.profiles.first?.associatedSpaceName == nil)

            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.first?.associatedSpaceKey == nil)
            #expect(reloaded.profiles.first?.associatedSpaceName == nil)
        }
    }

    @Test("A manifest written before Space associations existed still loads")
    func legacyManifestDecodes() throws {
        try withManager(seeding: ["Legacy"]) { manager, _ in
            // seedManifest writes metadata without the Space fields, which
            // is exactly what a pre-feature manifest looks like on disk.
            #expect(manager.profiles.count == 1)
            #expect(manager.profiles.first?.associatedSpaceKey == nil)
            #expect(manager.profiles.first?.associatedSpaceName == nil)
        }
    }

    // MARK: Uniqueness

    @Test("Assigning a Space to a second profile takes it from the first")
    func spaceAssociationIsUnique() throws {
        try withManager(seeding: ["One", "Two"]) { manager, _ in
            let first = try #require(manager.profiles.first { $0.name == "One" }?.id)
            let second = try #require(manager.profiles.first { $0.name == "Two" }?.id)

            manager.setAssociatedSpace(key: "SPACE-UUID-A", spaceName: "Desktop 1", forProfileID: first)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", spaceName: "Desktop 1", forProfileID: second)

            #expect(manager.profiles.first { $0.id == first }?.associatedSpaceKey == nil)
            #expect(manager.profiles.first { $0.id == first }?.associatedSpaceName == nil)
            #expect(manager.profiles.first { $0.id == second }?.associatedSpaceKey == "SPACE-UUID-A")
        }
    }

    @Test("Moving a profile to another Space leaves the old Space unassigned")
    func reassigningReleasesThePreviousSpace() throws {
        try withManager(seeding: ["One"]) { manager, _ in
            let id = try #require(manager.profiles.first?.id)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", forProfileID: id)

            manager.setAssociatedSpace(key: "SPACE-UUID-B", forProfileID: id)

            #expect(manager.profile(forSpaceKey: "SPACE-UUID-A") == nil)
            #expect(manager.profile(forSpaceKey: "SPACE-UUID-B")?.id == id)
        }
    }

    // MARK: Lookup

    @Test("A Space key resolves back to the profile that holds it")
    func spaceLookupFindsItsProfile() throws {
        try withManager(seeding: ["One", "Two"]) { manager, _ in
            let second = try #require(manager.profiles.first { $0.name == "Two" }?.id)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", forProfileID: second)

            #expect(manager.profile(forSpaceKey: "SPACE-UUID-A")?.id == second)
            #expect(manager.profile(forSpaceKey: "SPACE-UUID-B") == nil)
        }
    }

    @Test("Space and display associations are independent")
    func spaceAndDisplayAssociationsCoexist() throws {
        try withManager(seeding: ["Desk"]) { manager, _ in
            let id = try #require(manager.profiles.first?.id)

            manager.setAssociatedDisplay(uuid: "UUID-A", forProfileID: id)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", forProfileID: id)

            #expect(manager.profiles.first?.associatedDisplayUUID == "UUID-A")
            #expect(manager.profiles.first?.associatedSpaceKey == "SPACE-UUID-A")

            manager.setAssociatedSpace(key: nil, forProfileID: id)
            #expect(manager.profiles.first?.associatedDisplayUUID == "UUID-A")
            #expect(manager.profiles.first?.associatedSpaceKey == nil)

            manager.setAssociatedSpace(key: "SPACE-UUID-A", forProfileID: id)
            manager.setAssociatedDisplay(uuid: nil, forProfileID: id)
            #expect(manager.profiles.first?.associatedDisplayUUID == nil)
            #expect(manager.profiles.first?.associatedSpaceKey == "SPACE-UUID-A")
        }
    }

    // MARK: Export / import

    @Test("A Space association survives a single-profile export and import")
    func singleExportRoundTripsTheSpace() throws {
        try withManager(seeding: ["Exported"]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", spaceName: "Desktop 3", forProfileID: id)
            let file = tmp.appendingPathComponent("export.json")

            try manager.exportProfile(id: id, to: file)
            try manager.importProfile(from: file)

            // The import reconciles ownership through the setter, so the
            // freshly imported copy takes the Space from the original.
            #expect(manager.profiles.count == 2)
            let imported = try #require(manager.profiles.first { $0.id != id })
            #expect(imported.associatedSpaceKey == "SPACE-UUID-A")
            #expect(imported.associatedSpaceName == "Desktop 3")
            #expect(manager.profiles.first { $0.id == id }?.associatedSpaceKey == nil)
            #expect(manager.profile(forSpaceKey: "SPACE-UUID-A")?.id == imported.id)
        }
    }

    @Test("A bundle export carries every profile's Space association")
    func bundleExportRoundTripsTheSpaces() throws {
        try withManager(seeding: ["One", "Two"]) { manager, tmp in
            let first = try #require(manager.profiles.first { $0.name == "One" }?.id)
            let second = try #require(manager.profiles.first { $0.name == "Two" }?.id)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", spaceName: "Desktop 1", forProfileID: first)
            manager.setAssociatedSpace(key: "SPACE-UUID-B", spaceName: "Desktop 2", forProfileID: second)

            let json = try #require(manager.exportAllProfiles())
            let file = tmp.appendingPathComponent("bundle.json")
            try Data(json.utf8).write(to: file)

            let fresh = ProfileManager(profilesDirectory: tmp.appendingPathComponent("fresh", isDirectory: true))
            try fresh.importProfile(from: file)

            #expect(fresh.profiles.count == 2)
            #expect(fresh.profile(forSpaceKey: "SPACE-UUID-A")?.name == "One")
            #expect(fresh.profile(forSpaceKey: "SPACE-UUID-A")?.associatedSpaceName == "Desktop 1")
            #expect(fresh.profile(forSpaceKey: "SPACE-UUID-B")?.name == "Two")
            #expect(fresh.profile(forSpaceKey: "SPACE-UUID-B")?.associatedSpaceName == "Desktop 2")
        }
    }

    @Test("An export made before Space associations existed still imports")
    func legacyExportImports() throws {
        try withManager(seeding: ["Exported"]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            let file = tmp.appendingPathComponent("legacy.json")
            try manager.exportProfile(id: id, to: file)

            // Strip the Space keys the way an older build's export lacks them.
            var object = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            )
            var entries = try #require(object["entries"] as? [[String: Any]])
            entries[0].removeValue(forKey: "associatedSpaceKey")
            entries[0].removeValue(forKey: "associatedSpaceName")
            object["entries"] = entries
            try JSONSerialization.data(withJSONObject: object).write(to: file)

            try manager.importProfile(from: file)

            #expect(manager.profiles.count == 2)
            #expect(manager.profiles.allSatisfy { $0.associatedSpaceKey == nil })
        }
    }

    // MARK: - Helpers

    /// Runs body against a ProfileManager pointed at a fresh temporary
    /// directory seeded with one profile per name, and removes the directory
    /// after.
    private func withManager(
        seeding names: [String],
        _ body: (ProfileManager, URL) throws -> Void
    ) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try seedManifest(with: names.map(makeProfile), into: tmp)
        try body(ProfileManager(profilesDirectory: tmp), tmp)
    }

    /// Builds a profile with every field at its decoded default, which is
    /// all these tests need: they exercise the manifest, not the content.
    private func makeProfile(named name: String) -> Profile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(#"{"name": "\#(name)"}"#.utf8)
        // A profile with only a name is the documented minimum for
        // Profile.init(from:); a failure here is a test-fixture bug.
        // swiftlint:disable:next force_try
        return try! decoder.decode(Profile.self, from: data)
    }

    /// Writes each profile's JSON plus a profiles.json manifest, so a
    /// freshly constructed ProfileManager loads them the way it would in
    /// production. The metadata carries no Space fields, matching a manifest
    /// written before the feature existed.
    private func seedManifest(with profiles: [Profile], into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

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
        try encoder.encode(metadata).write(
            to: directory.appendingPathComponent("profiles.json"),
            options: .atomic
        )
    }
}
