//
//  ProfileLaunchApplyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// 2026-10-22: every launch put the display's profile back, so an item the
/// user had dragged into Always Hidden returned to Hidden after a logout.
@MainActor
@Suite("A profile already active at launch keeps the live layout", .serialized)
struct ProfileLaunchApplyTests {
    private let work = UUID()
    private let home = UUID()
    private let suites = ScratchSuites(prefix: "ProfileLaunchApplyTests")

    @Test func theProfileActiveAtQuitIsKept() {
        #expect(!ProfileLaunchApply.applies(profileID: work, activeProfileID: nil, lastActiveProfileID: work, reappliesAtLaunch: false))
    }

    @Test func aProfileThatAppliesAtLaunchIsApplied() {
        #expect(ProfileLaunchApply.applies(profileID: work, activeProfileID: nil, lastActiveProfileID: work, reappliesAtLaunch: true))
    }

    @Test func anotherProfileIsApplied() {
        #expect(ProfileLaunchApply.applies(profileID: work, activeProfileID: nil, lastActiveProfileID: home, reappliesAtLaunch: false))
    }

    @Test func aSwitchLaterInTheSessionIsApplied() {
        #expect(ProfileLaunchApply.applies(profileID: work, activeProfileID: home, lastActiveProfileID: work, reappliesAtLaunch: false))
    }

    @Test func theRecordRoundTripsAndKeepingSettlesToo() throws {
        let defaults = try #require(suites.make())
        let record = ProfileLaunchApply.Record(defaults: defaults)
        #expect(record.lastActiveProfileID == nil)
        record.keep(work)
        #expect(record.lastActiveProfileID == work)
        #expect(ProfileSettleReapply.Record(defaults: defaults).lastSettledProfileID == work)
        record.lastActiveProfileID = nil
        #expect(record.lastActiveProfileID == nil)
    }

    @Test func theManagerKeepsTheProfileActiveAtQuit() throws {
        let defaults = try #require(suites.make())
        try ProfileTestDirectory.withManager(seeding: ["Default"], launchRecord: .init(defaults: defaults)) { manager, _ in
            let meta = try #require(manager.profiles.first)
            ProfileLaunchApply.Record(defaults: defaults).lastActiveProfileID = meta.id

            #expect(manager.keepsLiveLayoutAtLaunch(meta))
            #expect(manager.activeProfileID == meta.id)
            #expect(ProfileSettleReapply.Record(defaults: defaults).lastSettledProfileID == meta.id)
            #expect(!manager.keepsLiveLayoutAtLaunch(meta), "a later switch applies as before")
        }
    }

    @Test func aFocusFilterAtLaunchKeepsTheProfileActiveAtQuit() async throws {
        let defaults = try #require(suites.make())
        let tmp = try ProfileTestDirectory.make(seeding: ["Default"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let id = try #require(ProfileManager(profilesDirectory: tmp).profiles.first?.id)
        ProfileLaunchApply.Record(defaults: defaults).lastActiveProfileID = id
        let manager = ProfileManager(profilesDirectory: tmp, launchRecord: .init(defaults: defaults))

        await manager.applyFocusFilterProfile(requested: id.uuidString)

        #expect(manager.activeProfileID == id)
        #expect(ProfileSettleReapply.Record(defaults: defaults).lastSettledProfileID == id)
    }

    @Test func theManagerAppliesAProfileSetToApplyAtLaunch() throws {
        let defaults = try #require(suites.make())
        try ProfileTestDirectory.withManager(seeding: ["Default"], launchRecord: .init(defaults: defaults)) { manager, _ in
            let id = try #require(manager.profiles.first?.id)
            ProfileLaunchApply.Record(defaults: defaults).lastActiveProfileID = id
            manager.setLayoutBehavior(reappliesAtLaunch: true, forProfileID: id)

            #expect(!manager.keepsLiveLayoutAtLaunch(try #require(manager.profiles.first)))
            #expect(manager.activeProfileID == nil)
        }
    }

    @Test func duplicatesAndExportsCarryTheSwitches() throws {
        try ProfileTestDirectory.withManager(seeding: ["Default"]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            manager.setLayoutBehavior(keepsChanges: false, reappliesAtLaunch: true, forProfileID: id)

            try manager.duplicateProfile(id: id, newName: "Copy")
            let copy = try #require(manager.profiles.first { $0.name == "Copy" })
            #expect(!copy.keepsLayoutChanges)
            #expect(copy.reappliesAtLaunch)

            let file = tmp.appendingPathComponent("export.json")
            try manager.exportProfile(id: id, to: file)
            try manager.importProfile(from: file)
            let imported = try #require(manager.profiles.last)
            #expect(imported.id != id)
            #expect(!imported.keepsLayoutChanges)
            #expect(imported.reappliesAtLaunch)
        }
    }

    @Test func theSwitchesPersistAndDefaultForOldManifests() throws {
        try ProfileTestDirectory.withManager(seeding: ["Default"]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            #expect(manager.profiles.first?.keepsLayoutChanges == true)
            #expect(manager.profiles.first?.reappliesAtLaunch == false)

            manager.setLayoutBehavior(keepsChanges: false, reappliesAtLaunch: true, forProfileID: id)
            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.first?.keepsLayoutChanges == false)
            #expect(reloaded.profiles.first?.reappliesAtLaunch == true)

            manager.setLayoutBehavior(forProfileID: UUID())
            #expect(ProfileManager(profilesDirectory: tmp).profiles.first?.keepsLayoutChanges == false)
        }
    }
}

/// A ProfileManager over a temporary directory seeded with named profiles.
@MainActor
enum ProfileTestDirectory {
    static func withManager(
        seeding names: [String],
        launchRecord: ProfileLaunchApply.Record? = nil,
        _ body: (ProfileManager, URL) throws -> Void
    ) throws {
        let tmp = try make(seeding: names)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try body(ProfileManager(profilesDirectory: tmp, launchRecord: launchRecord), tmp)
    }

    /// A new temporary directory holding the named profiles and their manifest. The caller removes it.
    static func make(seeding names: [String]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var metadata = [ProfileMetadata]()
        for name in names {
            let profile = try decoder.decode(Profile.self, from: Data(#"{"name": "\#(name)"}"#.utf8))
            try encoder.encode(profile).write(to: tmp.appendingPathComponent("\(profile.id.uuidString).json"))
            metadata.append(ProfileMetadata(id: profile.id, name: profile.name, createdAt: profile.createdAt, modifiedAt: profile.modifiedAt))
        }
        try encoder.encode(metadata).write(to: tmp.appendingPathComponent("profiles.json"))
        return tmp
    }
}
