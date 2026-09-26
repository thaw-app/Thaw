//
//  ProfileManagerDeleteTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Regression lock for `ProfileManager.deleteProfile(id:)` when the
/// profile's on-disk JSON file is already missing.
///
/// `FileManager.removeItem` throws when the file is already gone (out-of-band
/// deletion, cloud-sync churn, a partial earlier delete). Removing the file
/// before the manifest entry left the profile stuck in the UI for good.
///
/// Serialized to match `ProfileManagerCRUDTests`: both drive a real
/// `ProfileManager` over on-disk state.
@MainActor
@Suite("Profile manager delete", .serialized)
final class ProfileManagerDeleteTests {
    /// A fresh directory per test, since Swift Testing builds a new suite
    /// instance for every case.
    private let tmp: URL

    init() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// The JSON file is deleted out-of-band, then `deleteProfile(id:)` must not
    /// throw and the manifest entry must be gone. The bare `try` is itself an
    /// assertion.
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

        // Reload from disk to prove the entry was persisted away, not just
        // dropped from this instance.
        let reloaded = ProfileManager(profilesDirectory: tmp)
        #expect(!reloaded.profiles.contains { $0.id == profile.id })
    }

    /// The second call deletes an already-absent file and entry, and must
    /// not throw either.
    @Test("Deleting the same profile twice throws neither time")
    func deleteProfileCalledTwiceDoesNotThrowEitherTime() throws {
        let profile = makeProfile()
        try seedManifest(with: [profile], into: tmp)
        let profileManager = ProfileManager(profilesDirectory: tmp)

        try profileManager.deleteProfile(id: profile.id)
        try profileManager.deleteProfile(id: profile.id)

        #expect(!profileManager.profiles.contains { $0.id == profile.id })
    }

    /// Happy path: `deleteProfile(id:)` removes the file and the manifest
    /// entry. The bare `try` asserts it doesn't throw.
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
