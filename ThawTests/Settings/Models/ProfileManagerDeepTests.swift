//
//  ProfileManagerDeepTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the ``ProfileManager`` failure paths other suites miss: the
/// `do`/`catch` blocks that swallow I/O errors in `ensureDirectoryExists` and
/// `saveManifest`, and the already-active short circuit in
/// `applyFocusFilterProfile`.
///
/// A file at the profiles-directory path makes `fileExists` true and skips
/// `createDirectory`, so these cases block a parent component instead, and
/// park a directory on the manifest path so its write fails.
///
/// Failure cases assert through a second `ProfileManager` over the same
/// directory, since an in-memory assertion passes either way.
///
/// Not covered: anything that needs a live `AppState`, and
/// `captureCurrentLayout`'s item-section inversion, whose inputs are private
/// to `MenuBarItemManager`.
@MainActor
@Suite("Profile manager deep coverage", .serialized)
struct ProfileManagerDeepTests {
    // MARK: - Uncreatable Profiles Directory

    @Test("A profiles directory whose parent is a file cannot be created, and the manager still starts empty")
    func uncreatableProfilesDirectoryStartsEmpty() throws {
        try withTemporaryDirectory { tmp in
            let unreachable = try makeUncreatableDirectoryURL(in: tmp)

            let manager = ProfileManager(profilesDirectory: unreachable)

            #expect(manager.profiles.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: unreachable.path))
        }
    }

    @Test("A manager whose directory could not be created still accepts mutations, and persists none of them")
    func uncreatableProfilesDirectoryAcceptsMutationsWithoutPersistingThem() throws {
        try withTemporaryDirectory { tmp in
            let unreachable = try makeUncreatableDirectoryURL(in: tmp)
            let manager = ProfileManager(profilesDirectory: unreachable)

            // Both of these end in saveManifest, whose write cannot land.
            // Neither may trap: the manager is constructed at launch, long
            // before anything can tell the user their profiles are gone.
            manager.setAssociatedDisplay(uuid: "display-1", displayName: "Display", forProfileID: UUID())
            manager.setAssociatedDisplay(uuid: nil, forDisplayUUID: "display-1")

            #expect(manager.profiles.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: unreachable.path))
            #expect(ProfileManager(profilesDirectory: unreachable).profiles.isEmpty)
        }
    }

    @Test("A manager whose directory could not be created reports a delete as failed")
    func uncreatableProfilesDirectoryReportsDeleteAsFailed() throws {
        try withTemporaryDirectory { tmp in
            let unreachable = try makeUncreatableDirectoryURL(in: tmp)
            let manager = ProfileManager(profilesDirectory: unreachable)

            // `deleteProfile` swallows only `CocoaError.fileNoSuchFile`. Here the
            // parent isn't a directory, so removal fails with
            // `NSFileWriteUnknownError` (512) and propagates, so a broken
            // profiles directory isn't reported as a clean delete.
            #expect(throws: (any Error).self) {
                try manager.deleteProfile(id: UUID())
            }

            #expect(manager.profiles.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: unreachable.path))
        }
    }

    // MARK: - Unwritable Manifest

    @Test("A rename whose manifest write fails still reaches the profile file")
    func renameSurvivesAFailedManifestWrite() throws {
        try withTemporaryDirectory { tmp in
            let original = makeProfile(named: "Before")
            try seedManifest(with: [original], into: tmp)

            let manager = ProfileManager(profilesDirectory: tmp)
            #expect(manager.profiles.count == 1)

            let sentinel = try blockManifestPath(in: tmp)

            try manager.renameProfile(id: original.id, to: "After")

            // The per-profile JSON is written before the manifest, so it lands.
            #expect(manager.profiles.first?.name == "After")
            #expect(try manager.loadProfile(id: original.id).name == "After")

            // The manifest write failed: it neither replaced the occupied path
            // nor reached disk, so a reloaded manager sees no profiles at all.
            #expect(FileManager.default.fileExists(atPath: sentinel.path))
            #expect(isDirectory(at: tmp.appendingPathComponent("profiles.json")))
            #expect(ProfileManager(profilesDirectory: tmp).profiles.isEmpty)
        }
    }

    @Test("A delete whose manifest write fails still removes the profile file")
    func deleteSurvivesAFailedManifestWrite() throws {
        try withTemporaryDirectory { tmp in
            let doomed = makeProfile(named: "Doomed")
            let kept = makeProfile(named: "Kept")
            try seedManifest(with: [doomed, kept], into: tmp)

            let manager = ProfileManager(profilesDirectory: tmp)
            #expect(manager.profiles.count == 2)

            let sentinel = try blockManifestPath(in: tmp)

            try manager.deleteProfile(id: doomed.id)

            #expect(manager.profiles.count == 1)
            #expect(manager.profiles.first?.id == kept.id)
            #expect(!FileManager.default.fileExists(atPath: profileURL(for: doomed.id, in: tmp).path))
            #expect(FileManager.default.fileExists(atPath: sentinel.path))
            #expect(ProfileManager(profilesDirectory: tmp).profiles.isEmpty)
        }
    }

    @Test("A display association whose manifest write fails is lost on reload")
    func displayAssociationIsLostWhenTheManifestWriteFails() throws {
        try withTemporaryDirectory { tmp in
            let profile = makeProfile(named: "Desk")
            try seedManifest(with: [profile], into: tmp)

            let manager = ProfileManager(profilesDirectory: tmp)
            let sentinel = try blockManifestPath(in: tmp)

            manager.setAssociatedDisplay(uuid: "display-1", displayName: "Desk Display", forProfileID: profile.id)

            // The association lives only in the manifest, so in memory it took.
            #expect(manager.profiles.first?.associatedDisplayUUID == "display-1")
            #expect(FileManager.default.fileExists(atPath: sentinel.path))
            #expect(ProfileManager(profilesDirectory: tmp).profiles.isEmpty)
        }
    }

    @Test("A spacing broadcast whose manifest write fails still rewrites every profile file")
    func spacingBroadcastSurvivesAFailedManifestWrite() throws {
        try withTemporaryDirectory { tmp in
            let profile = makeProfile(named: "Desk")
            try seedManifest(with: [profile], into: tmp)

            let manager = ProfileManager(profilesDirectory: tmp)
            let sentinel = try blockManifestPath(in: tmp)

            try manager.updateAllProfilesItemSpacingOffset(displayUUID: "display-1", offset: 12)

            let reloaded = try manager.loadProfile(id: profile.id)
            #expect(reloaded.displayConfigurations["display-1"]?.itemSpacingOffset == 12)
            #expect(FileManager.default.fileExists(atPath: sentinel.path))
            #expect(ProfileManager(profilesDirectory: tmp).profiles.isEmpty)
        }
    }

    // MARK: - Focus Filter Re-Request

    /// The short circuit only flips the private `focusFilterActive` flag. What
    /// is assertable: a repeat request leaves the active profile alone and
    /// schedules no second layout pass, which would churn every menu bar item.
    @Test("A focus filter request naming the already-active profile changes nothing")
    func focusFilterRequestForTheActiveProfileIsInert() async throws {
        let seed = makeProfile(named: "Focused")

        try await withTemporaryDirectory { tmp in
            try seedManifest(with: [seed], into: tmp)
            let manager = ProfileManager(profilesDirectory: tmp)
            manager.activeProfileID = seed.id

            try await withScratchDefaults { suite in
                suite.set(seed.id.uuidString, forKey: "FocusFilterRequestedProfileID")
                await manager.applyFocusFilterProfile()
            }

            #expect(manager.activeProfileID == seed.id)
            #expect(manager.layoutTask == nil)
            #expect(manager.profiles.count == 1)
        }
    }

    @Test("A focus filter request naming the active profile is inert even when its file is gone")
    func focusFilterRequestForTheActiveProfileIsInertWithoutItsFile() async throws {
        let seed = makeProfile(named: "Focused")

        try await withTemporaryDirectory { tmp in
            try seedManifest(with: [seed], into: tmp)
            try FileManager.default.removeItem(at: profileURL(for: seed.id, in: tmp))

            let manager = ProfileManager(profilesDirectory: tmp)
            manager.activeProfileID = seed.id

            // The short circuit runs before the load, so a missing file is
            // never reached and nothing is logged as a failure.
            try await withScratchDefaults { suite in
                suite.set(seed.id.uuidString, forKey: "FocusFilterRequestedProfileID")
                await manager.applyFocusFilterProfile()
            }

            #expect(manager.activeProfileID == seed.id)
            #expect(manager.layoutTask == nil)
        }
    }

    // MARK: - Helpers

    /// Runs `body` against a fresh, empty temporary directory and removes it
    /// afterwards.
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try body(tmp)
    }

    /// Async counterpart to ``withTemporaryDirectory(_:)``.
    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try await body(tmp)
    }

    /// Returns a URL whose parent component is a regular file, so
    /// `createDirectory(withIntermediateDirectories:)` cannot succeed there.
    ///
    /// This leaves `fileExists` false and reaches the catch, and unlike a
    /// permissions block it also fails for a root-run test host.
    private func makeUncreatableDirectoryURL(in directory: URL) throws -> URL {
        let blocker = directory.appendingPathComponent("occupied", isDirectory: false)
        try Data("not a directory".utf8).write(to: blocker, options: .atomic)
        return blocker.appendingPathComponent("Profiles", isDirectory: true)
    }

    /// Replaces `profiles.json` with a non-empty directory, so every later
    /// manifest write fails: an atomic write renames its scratch file onto the
    /// destination, and a file can never be renamed over a directory.
    ///
    /// Returns the sentinel inside, whose survival proves the failed write left
    /// the occupied path alone.
    @discardableResult
    private func blockManifestPath(in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let manifest = directory.appendingPathComponent("profiles.json")

        if fileManager.fileExists(atPath: manifest.path) {
            try fileManager.removeItem(at: manifest)
        }
        try fileManager.createDirectory(at: manifest, withIntermediateDirectories: false)

        let sentinel = manifest.appendingPathComponent("sentinel")
        try Data("sentinel".utf8).write(to: sentinel, options: .atomic)
        return sentinel
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    private func profileURL(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
