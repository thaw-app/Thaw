//
//  ProfileManagerDeleteTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Regression lock for `ProfileManager.deleteProfile(id:)` when the
/// profile's on-disk JSON file is already missing.
///
/// The bug: `deleteProfile` removed the file before updating the in-memory
/// `profiles` list. `FileManager.removeItem` throws when the file is
/// already gone (out-of-band deletion, cloud-sync churn, a previous
/// partially-failed delete), which meant the manifest entry was never
/// cleaned up, leaving the profile stuck in the UI forever — and every
/// subsequent delete attempt failed the same way.
///
/// These tests drive the real `ProfileManager` against an injected
/// temporary profiles directory, never the user's real profile folder.
///
/// Serialized to match `ProfileManagerCRUDTests`: both drive a real
/// `ProfileManager` on the main actor over on-disk state.
@MainActor
@Suite("Profile manager delete", .serialized)
final class ProfileManagerDeleteTests {
    /// A fresh directory per test. Swift Testing builds a new suite instance
    /// for every case, so `init`/`deinit` give the same per-test setup and
    /// teardown the XCTest `setUp`/`tearDown` pair did.
    private let tmp: URL

    init() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// The regression: the profile's JSON file is deleted behind the
    /// manager's back (simulating out-of-band removal), then
    /// `deleteProfile(id:)` is called. It must not throw, and the manifest
    /// entry must be gone afterward.
    ///
    /// The bare `try profileManager.deleteProfile(id:)` below is itself an
    /// assertion: a throw fails the test, which is exactly the regression.
    @Test("Deleting a profile whose file already vanished still clears the manifest entry")
    func deleteProfileWithMissingFileDoesNotThrowAndRemovesManifestEntry() throws {
        let profile = makeProfile()
        try seedManifest(with: [profile], into: tmp)
        let profileManager = ProfileManager(profilesDirectory: tmp)
        #expect(profileManager.profiles.contains { $0.id == profile.id })

        // Simulate the file vanishing out-of-band before delete is called.
        try FileManager.default.removeItem(
            at: tmp.appendingPathComponent("\(profile.id.uuidString).json")
        )

        try profileManager.deleteProfile(id: profile.id)
        #expect(!profileManager.profiles.contains { $0.id == profile.id })

        // The in-memory list is not the regression: the manifest on disk is.
        // Reload from the same directory to prove the entry was persisted
        // away, not just dropped from this instance.
        let reloaded = ProfileManager(profilesDirectory: tmp)
        #expect(!reloaded.profiles.contains { $0.id == profile.id })
    }

    /// Calling `deleteProfile(id:)` twice in a row must not throw the
    /// second time either: the file is gone after the first call, and the
    /// manifest entry with it, so the second call is a no-op deletion of an
    /// already-absent file and an already-absent entry.
    ///
    /// Neither `try` below is allowed to throw; that not-throwing is the
    /// assertion this case exists for.
    @Test("Deleting the same profile twice throws neither time")
    func deleteProfileCalledTwiceDoesNotThrowEitherTime() throws {
        let profile = makeProfile()
        try seedManifest(with: [profile], into: tmp)
        let profileManager = ProfileManager(profilesDirectory: tmp)

        try profileManager.deleteProfile(id: profile.id)
        try profileManager.deleteProfile(id: profile.id)

        #expect(!profileManager.profiles.contains { $0.id == profile.id })
    }

    /// Happy path: the file exists on disk, `deleteProfile(id:)` removes it
    /// and the manifest entry, with no throw — the bare `try` carries that
    /// last part of the assertion.
    @Test("Deleting a profile removes both its file and its manifest entry")
    func deleteProfileHappyPathRemovesFileAndManifestEntry() throws {
        let profile = makeProfile()
        try seedManifest(with: [profile], into: tmp)
        let profileManager = ProfileManager(profilesDirectory: tmp)
        let fileURL = tmp.appendingPathComponent("\(profile.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        try profileManager.deleteProfile(id: profile.id)

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(!profileManager.profiles.contains { $0.id == profile.id })
    }
}
