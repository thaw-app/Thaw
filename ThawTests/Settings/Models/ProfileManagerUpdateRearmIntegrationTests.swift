//
//  ProfileManagerUpdateRearmIntegrationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// End-to-end regression lock for the update-re-arms-cache wiring.
///
/// Drives the real `updateProfileLayout` path against a temporary profiles
/// directory and a standalone MenuBarItemManager. Fails if the re-arm wiring
/// is removed from `updateProfileLayout`.
///
/// Serialized because `withScratchDefaults` swaps the process-wide `Defaults`
/// store.
@MainActor
@Suite("Profile manager update re-arm integration", .serialized)
final class ProfileManagerRearmIntegrationTests {
    private let savedSectionOrderKey = "MenuBarItemManager.savedSectionOrder"

    /// The user moves an item from Always-Hidden to Hidden, then updates the
    /// active profile's layout. The cached spec must follow to Hidden, or a
    /// late-arrival re-sort drags the item back into Always-Hidden.
    @Test("Updating the active profile's layout re-arms the cache end to end")
    func updatingActiveProfileLayoutRearmsCacheEndToEnd() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let profileManager = ProfileManager(profilesDirectory: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let itemManager = MenuBarItemManager()
        let uid = "com.example.app:Item-0"

        // A profile exists on disk and is the active one.
        let profile = makeProfile(savedSectionOrder: ["alwaysHidden": [uid]])
        try writeProfile(profile, into: tmp)
        profileManager.activeProfileID = profile.id

        // Cache armed as if the profile were applied: item in Always-Hidden.
        itemManager.rearmActiveProfileLayout(
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: ["alwaysHidden": [uid]],
            itemSectionMap: [uid: "alwaysHidden"],
            itemOrder: ["alwaysHidden": [uid]]
        )
        #expect(
            itemManager.activeProfileLayout?.sectionOrder == ["alwaysHidden": [uid]],
            "Precondition: cache reflects the applied (Always-Hidden) spec"
        )

        // The user dragged the item to Hidden (the live layout is now B), then
        // updates the active profile's layout. Both the seed and the capture
        // read go through the scratch store.
        try withScratchDefaults { suite in
            suite.set(["hidden": [uid]], forKey: savedSectionOrderKey)
            try profileManager.updateProfileLayout(id: profile.id, itemManager: itemManager)
        }

        // The cache now reflects Hidden, so the next late-arrival re-sort
        // targets the updated layout instead of reverting to Always-Hidden.
        #expect(
            itemManager.activeProfileLayout?.sectionOrder == ["hidden": [uid]],
            "Updating the active profile must re-arm the cache to the new layout"
        )
    }

    /// Updating a profile that is not the active one must not touch the cache,
    /// even end-to-end: the disk write happens but the in-memory spec is left
    /// pointing at the active profile's layout.
    @Test("Updating an inactive profile leaves the cache alone")
    func updatingInactiveProfileDoesNotRearmCache() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let profileManager = ProfileManager(profilesDirectory: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let itemManager = MenuBarItemManager()
        let uid = "com.example.app:Item-0"

        let inactiveProfile = makeProfile(savedSectionOrder: ["alwaysHidden": [uid]])
        try writeProfile(inactiveProfile, into: tmp)
        // A different profile is the active one.
        profileManager.activeProfileID = UUID()

        itemManager.rearmActiveProfileLayout(
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: ["alwaysHidden": [uid]],
            itemSectionMap: [uid: "alwaysHidden"],
            itemOrder: ["alwaysHidden": [uid]]
        )

        try withScratchDefaults { suite in
            suite.set(["hidden": [uid]], forKey: savedSectionOrderKey)
            try profileManager.updateProfileLayout(id: inactiveProfile.id, itemManager: itemManager)
        }

        #expect(
            itemManager.activeProfileLayout?.sectionOrder == ["alwaysHidden": [uid]],
            "Updating a non-active profile must leave the active cache untouched"
        )
    }

    // MARK: - Helpers

    private func writeProfile(_ profile: Profile, into directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(
            to: directory.appendingPathComponent("\(profile.id.uuidString).json"),
            options: .atomic
        )
    }
}
