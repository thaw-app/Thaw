//
//  ProfileImportPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
import ThawModuleKit
@testable import Thaw

/// A profile file can come from anyone, so importing it must stay bounded and switch nothing risky on.
@MainActor
@Suite("Profile import policy", .serialized)
struct ProfileImportPolicyTests {
    private static func makeProfile(named name: String) throws -> Profile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Profile.self, from: Data(#"{"name": "\#(name)"}"#.utf8))
    }

    private static func bundle(count: Int) throws -> ProfileExportBundle {
        try ProfileExportBundle(entries: (0 ..< count).map { index in
            try ProfileExportEntry(profile: makeProfile(named: "P\(index)"))
        })
    }

    private static func write(_ bundle: ProfileExportBundle, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(bundle).write(to: url)
    }

    @Test("A file with more profiles than the limit is refused")
    func tooManyProfilesAreRefused() throws {
        let bundle = try Self.bundle(count: ProfileImportPolicy.maxEntries + 1)
        #expect(throws: ProfileImportPolicy.ImportError.tooManyProfiles(ProfileImportPolicy.maxEntries + 1)) {
            try ProfileImportPolicy.validate(bundle)
        }
    }

    @Test("The refusal names the file's count and the limit")
    func refusalDescription() throws {
        let count = ProfileImportPolicy.maxEntries + 1
        let description = try #require(ProfileImportPolicy.ImportError.tooManyProfiles(count).errorDescription)
        #expect(description.contains("\(count)"))
        #expect(description.contains("\(ProfileImportPolicy.maxEntries)"))
    }

    @Test("A profile rebuilt from its content and metadata is the same profile")
    func metadataAndContentRoundTrip() throws {
        let source = try Self.makeProfile(named: "Desk")
        let created = Date(timeIntervalSince1970: 1000)
        let modified = Date(timeIntervalSince1970: 2000)
        let profile = Profile(id: source.id, name: "Desk", createdAt: created, modifiedAt: modified, content: source.content)

        let metadata = profile.metadata
        #expect(metadata.id == source.id)
        #expect(metadata.name == "Desk")
        #expect(metadata.createdAt == created)
        #expect(metadata.modifiedAt == modified)
        #expect(profile.hotkeys == source.hotkeys)
        #expect(profile.confirmSpacingRelaunch == source.confirmSpacingRelaunch)
    }

    @Test("Content built without the spacing fields takes their defaults")
    func contentDefaults() throws {
        let source = try Self.makeProfile(named: "Desk").content
        let content = ProfileContent(
            generalSettings: source.generalSettings,
            advancedSettings: source.advancedSettings,
            hotkeys: [:],
            displayConfigurations: [:],
            appearanceConfiguration: source.appearanceConfiguration,
            menuBarLayout: source.menuBarLayout
        )
        #expect(content.globalDisplayConfiguration == Defaults.DefaultValue.globalDisplayConfiguration)
        #expect(content.confirmSpacingRelaunch == Defaults.DefaultValue.confirmSpacingRelaunch)
        #expect(content.unconfirmedSpacingProfileScope == Defaults.DefaultValue.unconfirmedSpacingProfileScope)
        #expect(content.spacingApplyMode == nil)
        #expect(content.automation == nil)
    }

    @Test("A file at the limit is accepted")
    func limitIsAccepted() throws {
        try ProfileImportPolicy.validate(Self.bundle(count: ProfileImportPolicy.maxEntries))
    }

    @Test("Imported content arrives with hooks off and relaunch confirmation on")
    func contentIsMadeSafe() throws {
        var content = try Self.makeProfile(named: "Shared").content
        content.automation = ProfileAutomation(preHook: HookScript(path: "/tmp/pre.sh", isEnabled: true))
        content.confirmSpacingRelaunch = false

        let sanitized = ProfileImportPolicy.sanitized(content)

        #expect(sanitized.automation?.preHook?.isEnabled == false)
        #expect(sanitized.automation?.preHook?.path == "/tmp/pre.sh")
        #expect(sanitized.confirmSpacingRelaunch)
    }

    @Test("Saved orders are cut to the per-section limit")
    func savedOrdersAreCapped() throws {
        let limit = ProfileImportPolicy.maxIdentifiersPerSection
        let long = (0 ..< limit + 50).map { "com.app\($0):item:0" }
        var content = try Self.makeProfile(named: "Big").content
        content.menuBarLayout.savedSectionOrder = ["hidden": long, "visible": ["com.a:x:0"]]
        content.menuBarLayout.itemOrder = ["hidden": long]

        let sanitized = ProfileImportPolicy.sanitized(content)

        #expect(sanitized.menuBarLayout.savedSectionOrder["hidden"] == Array(long.prefix(limit)))
        #expect(sanitized.menuBarLayout.savedSectionOrder["visible"] == ["com.a:x:0"])
        #expect(sanitized.menuBarLayout.itemOrder?["hidden"]?.count == limit)
    }

    @Test("Importing an oversized file writes nothing")
    func oversizedImportWritesNothing() throws {
        try ProfileTestDirectory.withManager(seeding: ["Default"]) { manager, tmp in
            let file = tmp.appendingPathComponent("big.json")
            try Self.write(Self.bundle(count: ProfileImportPolicy.maxEntries + 1), to: file)
            let before = try FileManager.default.contentsOfDirectory(atPath: tmp.path).count

            #expect(throws: ProfileImportPolicy.ImportError.self) {
                try manager.importProfile(from: file)
            }
            #expect(manager.profiles.count == 1)
            #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path).count == before)
        }
    }

    @Test("An import stores capped orders and reconciles display ownership in one pass")
    func importStoresSanitizedProfiles() throws {
        try ProfileTestDirectory.withManager(seeding: ["Existing"]) { manager, tmp in
            let existing = try #require(manager.profiles.first?.id)
            manager.setAssociatedDisplay(uuid: "DISPLAY-A", displayName: "Studio", forProfileID: existing)

            var first = try Self.makeProfile(named: "First")
            first.menuBarLayout.savedSectionOrder = ["hidden": (0 ..< 5000).map { "com.app\($0):item:0" }]
            let second = try Self.makeProfile(named: "Second")
            let bundle = ProfileExportBundle(entries: [
                ProfileExportEntry(profile: first, associatedDisplayUUID: "DISPLAY-A", associatedDisplayName: "Studio"),
                ProfileExportEntry(profile: second, associatedDisplayUUID: "DISPLAY-A", associatedDisplayName: "Studio"),
            ])
            let file = tmp.appendingPathComponent("bundle.json")
            try Self.write(bundle, to: file)

            try manager.importProfile(from: file)

            #expect(manager.profiles.map(\.name) == ["Existing", "First", "Second"])
            #expect(manager.profiles.filter { $0.associatedDisplayUUID == "DISPLAY-A" }.map(\.name) == ["Second"])
            let storedFirst = try #require(manager.profiles.first { $0.name == "First" })
            let loaded = try manager.loadProfile(id: storedFirst.id)
            #expect(loaded.menuBarLayout.savedSectionOrder["hidden"]?.count == ProfileImportPolicy.maxIdentifiersPerSection)

            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.map(\.name) == ["Existing", "First", "Second"])
            #expect(reloaded.profiles.first { $0.associatedDisplayUUID == "DISPLAY-A" }?.name == "Second")
        }
    }
}
