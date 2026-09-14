//
//  ProfileManagerSectionOrderUpdateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers `ProfileManager.updateActiveProfileSectionOrder(_:identifiers:)`,
/// which the Sort A→Z action (#936) uses to persist a sorted section into the
/// active profile before re-applying, so `reapplyActiveProfile` reads the new
/// order instead of the stale on-disk one.
///
/// Drives the real ProfileManager against an injected temporary profiles
/// directory, mirroring ProfileManagerRearmIntegrationTests. Serialized
/// because it swaps the process-wide Defaults store via withScratchDefaults.
@MainActor
@Suite("Profile manager section-order update", .serialized)
final class ProfileManagerSectionOrderUpdateTests {
    private func makeManager(
        profiles: [Profile],
        activeID: UUID? = nil,
        setActiveID: Bool = true
    ) throws -> (ProfileManager, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try seedManifest(with: profiles, into: tmp)
        let manager = ProfileManager(profilesDirectory: tmp)
        if setActiveID {
            manager.activeProfileID = activeID ?? profiles.first?.id
        }
        return (manager, tmp)
    }

    @Test("A sorted section is written into the active profile's savedSectionOrder and itemOrder")
    func sortedSectionIsWrittenIntoActiveProfile() throws {
        let uidA = "com.example.appA:Item-0"
        let uidB = "com.example.appB:Item-0"
        let uidC = "com.example.appC:Item-0"
        let profile = makeProfile(savedSectionOrder: [
            "hidden": [uidB, uidA, uidC],
            "visible": [uidA],
        ])
        let (manager, tmp) = try makeManager(profiles: [profile])
        defer { try? FileManager.default.removeItem(at: tmp) }

        let succeeded = manager.updateActiveProfileSectionOrder(.hidden, identifiers: [uidA, uidB, uidC])
        #expect(succeeded)

        // Reload the profile from disk and read through resolvedItemOrder, the
        // path reapplyActiveProfile consults.
        let reloaded = try ProfileManager(profilesDirectory: tmp).loadProfile(id: profile.id)
        #expect(reloaded.menuBarLayout.savedSectionOrder["hidden"] == [uidA, uidB, uidC])
        #expect(reloaded.menuBarLayout.itemOrder?["hidden"] == [uidA, uidB, uidC])
        // Other sections are preserved, not dropped.
        #expect(reloaded.menuBarLayout.savedSectionOrder["visible"] == [uidA])
    }

    @Test("A missing itemOrder is seeded from the full savedSectionOrder, not an empty dict")
    func missingItemOrderSeedsFromSavedSectionOrder() throws {
        // A profile whose itemOrder is nil (legacy or pre-sort shape). The
        // update must seed itemOrder from the complete savedSectionOrder so
        // resolvedItemOrder keeps every section, instead of a single-section
        // dict shadowing the rest.
        let uidA = "com.example.appA:Item-0"
        let uidB = "com.example.appB:Item-0"
        var profile = makeProfile(savedSectionOrder: [
            "hidden": [uidA],
            "visible": [uidB],
        ])
        profile.menuBarLayout.itemOrder = nil
        let (manager, tmp) = try makeManager(profiles: [profile])
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(manager.updateActiveProfileSectionOrder(.hidden, identifiers: [uidA]))

        let reloaded = try ProfileManager(profilesDirectory: tmp).loadProfile(id: profile.id)
        // itemOrder now carries both sections (seeded from savedSectionOrder),
        // with the sorted section overwritten.
        #expect(reloaded.menuBarLayout.itemOrder?["hidden"] == [uidA])
        #expect(reloaded.menuBarLayout.itemOrder?["visible"] == [uidB],
                "the visible section must survive the seed, not be dropped")
    }

    @Test("Returns false and writes nothing when no profile is active")
    func noActiveProfileReturnsFalse() throws {
        let profile = makeProfile(savedSectionOrder: ["hidden": ["com.example.app:Item-0"]])
        let (manager, tmp) = try makeManager(profiles: [profile], activeID: nil, setActiveID: false)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(manager.updateActiveProfileSectionOrder(.hidden, identifiers: ["x"]) == false)

        // The on-disk profile is untouched.
        let reloaded = try ProfileManager(profilesDirectory: tmp).loadProfile(id: profile.id)
        #expect(reloaded.menuBarLayout.savedSectionOrder["hidden"] == ["com.example.app:Item-0"])
    }
}
