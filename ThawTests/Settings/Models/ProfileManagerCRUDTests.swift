//
//  ProfileManagerCRUDTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the ``ProfileManager`` surface that owns files and the manifest:
/// rename, duplicate, import/export, display association, hooks, and the
/// two broadcast writers.
///
/// `applyProfile` and `performSetup` need a live `AppState` and are out of
/// reach here; everything below runs against a real `ProfileManager` pointed
/// at a per-test temporary directory, so the on-disk JSON and the in-memory
/// manifest are both exercised for real.
///
/// Each case that mutates asserts against a *reloaded* manager where the
/// persisted state is what matters — an in-memory-only assertion would pass
/// for a change that never reached disk, which is the bug class
/// `ProfileManagerDeleteTests` was written for.
@MainActor
@Suite("Profile manager CRUD", .serialized)
struct ProfileManagerCRUDTests {
    // MARK: Rename

    @Test("Renaming rewrites both the profile file and the manifest")
    func renamePersists() throws {
        try withManager(seeding: [makeProfile(named: "Before")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)

            try manager.renameProfile(id: id, to: "After")

            #expect(manager.profiles.first?.name == "After")
            #expect(try manager.loadProfile(id: id).name == "After")
            #expect(ProfileManager(profilesDirectory: tmp).profiles.first?.name == "After")
        }
    }

    @Test("Renaming keeps the identifier and creation date")
    func renameKeepsIdentity() throws {
        try withManager(seeding: [makeProfile(named: "Before")]) { manager, _ in
            let original = try #require(manager.profiles.first)

            try manager.renameProfile(id: original.id, to: "After")

            let reloaded = try manager.loadProfile(id: original.id)
            #expect(reloaded.id == original.id)
            #expect(reloaded.createdAt == original.createdAt)
        }
    }

    @Test("Renaming an unknown profile throws")
    func renamingAnUnknownProfileThrows() throws {
        try withManager(seeding: []) { manager, _ in
            #expect(throws: (any Error).self) {
                try manager.renameProfile(id: UUID(), to: "Nope")
            }
        }
    }

    // MARK: Duplicate

    @Test("Duplicating adds a second profile with a new identifier")
    func duplicateAddsANewProfile() throws {
        try withManager(seeding: [makeProfile(named: "Original")]) { manager, tmp in
            let originalID = try #require(manager.profiles.first?.id)

            try manager.duplicateProfile(id: originalID, newName: "Copy")

            #expect(manager.profiles.count == 2)
            let copy = try #require(manager.profiles.first { $0.name == "Copy" })
            #expect(copy.id != originalID)
            #expect(ProfileManager(profilesDirectory: tmp).profiles.count == 2)
        }
    }

    @Test("A duplicate carries the original's content")
    func duplicateCopiesContent() throws {
        var seed = makeProfile(named: "Original")
        seed.displayConfigurations = ["UUID-A": .defaultConfiguration.withItemSpacingOffset(7)]

        try withManager(seeding: [seed]) { manager, _ in
            let originalID = try #require(manager.profiles.first?.id)

            try manager.duplicateProfile(id: originalID, newName: "Copy")

            let copyID = try #require(manager.profiles.first { $0.name == "Copy" }?.id)
            let copy = try manager.loadProfile(id: copyID)

            // The seeded per-display entry is the load-bearing assertion:
            // `duplicateProfile` rebuilds the copy from `original.content`,
            // and `Profile.content` is computed, so a field dropped from
            // either side of that round trip vanishes silently. Asserting a
            // `makeProfile` default instead would pass even then.
            #expect(copy.displayConfigurations["UUID-A"]?.itemSpacingOffset == 7)
            #expect(copy.content.generalSettings.rehideInterval == 15)
        }
    }

    @Test("Duplicating an unknown profile throws")
    func duplicatingAnUnknownProfileThrows() throws {
        try withManager(seeding: []) { manager, _ in
            #expect(throws: (any Error).self) {
                try manager.duplicateProfile(id: UUID(), newName: "Copy")
            }
        }
    }

    // MARK: Export / import

    @Test("An exported profile imports back as a new profile")
    func exportImportRoundTrips() throws {
        try withManager(seeding: [makeProfile(named: "Exported")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            let file = tmp.appendingPathComponent("export.json")

            try manager.exportProfile(id: id, to: file)
            #expect(FileManager.default.fileExists(atPath: file.path))

            try manager.importProfile(from: file)

            #expect(manager.profiles.count == 2)
            #expect(manager.profiles.filter { $0.name == "Exported" }.count == 2)
        }
    }

    @Test("An imported profile is given a fresh identifier")
    func importAssignsANewIdentifier() throws {
        try withManager(seeding: [makeProfile(named: "Exported")]) { manager, tmp in
            let originalID = try #require(manager.profiles.first?.id)
            let file = tmp.appendingPathComponent("export.json")
            try manager.exportProfile(id: originalID, to: file)

            try manager.importProfile(from: file)

            let ids = manager.profiles.map(\.id)
            #expect(Set(ids).count == 2, "an import must not collide with the profile it came from")
        }
    }

    @Test("Importing malformed JSON throws and adds nothing")
    func importingMalformedJSONThrows() throws {
        try withManager(seeding: [makeProfile(named: "Kept")]) { manager, tmp in
            let file = tmp.appendingPathComponent("bad.json")
            try Data("not a profile bundle".utf8).write(to: file)

            #expect(throws: (any Error).self) {
                try manager.importProfile(from: file)
            }
            #expect(manager.profiles.count == 1)
        }
    }

    @Test("Importing from a missing file throws")
    func importingAMissingFileThrows() throws {
        try withManager(seeding: []) { manager, tmp in
            #expect(throws: (any Error).self) {
                try manager.importProfile(from: tmp.appendingPathComponent("absent.json"))
            }
        }
    }

    @Test("Exporting every profile yields a bundle listing all of them")
    func exportAllListsEveryProfile() throws {
        try withManager(seeding: [makeProfile(named: "One"), makeProfile(named: "Two")]) { manager, _ in
            let json = try #require(manager.exportAllProfiles())

            #expect(json.contains("One"))
            #expect(json.contains("Two"))
        }
    }

    @Test("Exporting from an empty store still yields a bundle")
    func exportAllOnAnEmptyStore() throws {
        try withManager(seeding: []) { manager, _ in
            #expect(manager.exportAllProfiles() != nil)
        }
    }

    // MARK: Display association

    @Test("A display association persists to the manifest")
    func displayAssociationPersists() throws {
        try withManager(seeding: [makeProfile(named: "Desk")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)

            manager.setAssociatedDisplay(uuid: "UUID-A", displayName: "Studio Display", forProfileID: id)

            #expect(manager.profiles.first?.associatedDisplayUUID == "UUID-A")
            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.first?.associatedDisplayUUID == "UUID-A")
            #expect(reloaded.profiles.first?.associatedDisplayName == "Studio Display")
        }
    }

    @Test("Associating a display moves it off whichever profile held it")
    func displayAssociationIsExclusive() throws {
        try withManager(seeding: [makeProfile(named: "One"), makeProfile(named: "Two")]) { manager, _ in
            let first = try #require(manager.profiles.first { $0.name == "One" }?.id)
            let second = try #require(manager.profiles.first { $0.name == "Two" }?.id)

            manager.setAssociatedDisplay(uuid: "UUID-A", forProfileID: first)
            manager.setAssociatedDisplay(uuid: "UUID-A", forProfileID: second)

            #expect(manager.profiles.first { $0.id == first }?.associatedDisplayUUID == nil)
            #expect(manager.profiles.first { $0.id == second }?.associatedDisplayUUID == "UUID-A")
        }
    }

    @Test("Passing nil clears the association")
    func displayAssociationCanBeCleared() throws {
        try withManager(seeding: [makeProfile(named: "Desk")]) { manager, _ in
            let id = try #require(manager.profiles.first?.id)
            manager.setAssociatedDisplay(uuid: "UUID-A", forProfileID: id)

            manager.setAssociatedDisplay(uuid: nil, forProfileID: id)

            #expect(manager.profiles.first?.associatedDisplayUUID == nil)
        }
    }

    // MARK: Space association

    @Test("A Space association persists to the manifest")
    func spaceAssociationPersists() throws {
        try withManager(seeding: [makeProfile(named: "Writing")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)

            manager.setAssociatedSpace(key: "SPACE-UUID-A", spaceName: "Desktop 2", forProfileID: id)

            #expect(manager.profiles.first?.associatedSpaceKey == "SPACE-UUID-A")
            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.first?.associatedSpaceKey == "SPACE-UUID-A")
            #expect(reloaded.profiles.first?.associatedSpaceName == "Desktop 2")
        }
    }

    @Test("Associating a Space moves it off whichever profile held it")
    func spaceAssociationIsExclusive() throws {
        try withManager(seeding: [makeProfile(named: "One"), makeProfile(named: "Two")]) { manager, _ in
            let first = try #require(manager.profiles.first { $0.name == "One" }?.id)
            let second = try #require(manager.profiles.first { $0.name == "Two" }?.id)

            manager.setAssociatedSpace(key: "SPACE-UUID-A", forProfileID: first)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", forProfileID: second)

            #expect(manager.profiles.first { $0.id == first }?.associatedSpaceKey == nil)
            #expect(manager.profiles.first { $0.id == second }?.associatedSpaceKey == "SPACE-UUID-A")
        }
    }

    @Test("Passing nil clears the Space association and its cached label")
    func spaceAssociationCanBeCleared() throws {
        try withManager(seeding: [makeProfile(named: "Writing")]) { manager, _ in
            let id = try #require(manager.profiles.first?.id)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", spaceName: "Desktop 2", forProfileID: id)

            manager.setAssociatedSpace(key: nil, forProfileID: id)

            #expect(manager.profiles.first?.associatedSpaceKey == nil)
            #expect(manager.profiles.first?.associatedSpaceName == nil)
        }
    }

    @Test("A Space key resolves back to the profile that holds it")
    func spaceLookupFindsItsProfile() throws {
        try withManager(seeding: [makeProfile(named: "One"), makeProfile(named: "Two")]) { manager, _ in
            let second = try #require(manager.profiles.first { $0.name == "Two" }?.id)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", forProfileID: second)

            #expect(manager.profile(forSpaceKey: "SPACE-UUID-A")?.id == second)
            #expect(manager.profile(forSpaceKey: "SPACE-UUID-B") == nil)
        }
    }

    @Test("Space and display associations are independent")
    func spaceAndDisplayAssociationsCoexist() throws {
        try withManager(seeding: [makeProfile(named: "Desk")]) { manager, _ in
            let id = try #require(manager.profiles.first?.id)

            manager.setAssociatedDisplay(uuid: "UUID-A", forProfileID: id)
            manager.setAssociatedSpace(key: "SPACE-UUID-A", forProfileID: id)

            #expect(manager.profiles.first?.associatedDisplayUUID == "UUID-A")
            #expect(manager.profiles.first?.associatedSpaceKey == "SPACE-UUID-A")

            manager.setAssociatedSpace(key: nil, forProfileID: id)
            #expect(manager.profiles.first?.associatedDisplayUUID == "UUID-A")
        }
    }

    // MARK: Hooks

    @Test("An unset profile reports empty automation")
    func hooksDefaultToEmpty() throws {
        try withManager(seeding: [makeProfile(named: "Hooked")]) { manager, _ in
            let id = try #require(manager.profiles.first?.id)

            #expect(manager.hooks(forProfileID: id).isEmpty)
        }
    }

    @Test("An unknown profile reports empty automation rather than throwing")
    func hooksForAnUnknownProfileAreEmpty() throws {
        try withManager(seeding: []) { manager, _ in
            #expect(manager.hooks(forProfileID: UUID()).isEmpty)
        }
    }

    @Test("A hook set on one phase persists and leaves the other alone")
    func settingAHookPersists() throws {
        try withManager(seeding: [makeProfile(named: "Hooked")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            let hook = HookScript(path: "/tmp/pre.sh", timeoutSeconds: 5)

            try manager.setHook(hook, phase: .pre, forProfileID: id)

            let reloaded = ProfileManager(profilesDirectory: tmp)
            let automation = reloaded.hooks(forProfileID: id)
            #expect(automation.preHook?.path == "/tmp/pre.sh")
            #expect(automation.postHook == nil)
        }
    }

    @Test("Clearing the last hook empties the automation entirely")
    func clearingAHookEmptiesAutomation() throws {
        try withManager(seeding: [makeProfile(named: "Hooked")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            try manager.setHook(HookScript(path: "/tmp/pre.sh", timeoutSeconds: 5), phase: .pre, forProfileID: id)

            try manager.setHook(nil, phase: .pre, forProfileID: id)

            #expect(ProfileManager(profilesDirectory: tmp).hooks(forProfileID: id).isEmpty)
        }
    }

    @Test("Both phases can hold a hook at once")
    func bothPhasesCanBeSet() throws {
        try withManager(seeding: [makeProfile(named: "Hooked")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)

            try manager.setHook(HookScript(path: "/tmp/pre.sh", timeoutSeconds: 5), phase: .pre, forProfileID: id)
            try manager.setHook(HookScript(path: "/tmp/post.sh", timeoutSeconds: 5), phase: .post, forProfileID: id)

            let automation = ProfileManager(profilesDirectory: tmp).hooks(forProfileID: id)
            #expect(automation.preHook?.path == "/tmp/pre.sh")
            #expect(automation.postHook?.path == "/tmp/post.sh")
        }
    }

    // MARK: Broadcast writers

    @Test("A spacing broadcast reaches every profile")
    func spacingBroadcastReachesEveryProfile() throws {
        try withManager(seeding: [makeProfile(named: "One"), makeProfile(named: "Two")]) { manager, tmp in
            try manager.updateAllProfilesItemSpacingOffset(displayUUID: "UUID-A", offset: -6)

            let reloaded = ProfileManager(profilesDirectory: tmp)
            for meta in reloaded.profiles {
                let profile = try reloaded.loadProfile(id: meta.id)
                #expect(profile.displayConfigurations["UUID-A"]?.itemSpacingOffset == -6, "\(meta.name)")
            }
        }
    }

    @Test("A spacing broadcast leaves other displays untouched")
    func spacingBroadcastIsScopedToItsDisplay() throws {
        var seed = makeProfile(named: "One")
        seed.displayConfigurations = ["UUID-B": .defaultConfiguration.withItemSpacingOffset(3)]

        try withManager(seeding: [seed]) { manager, tmp in
            try manager.updateAllProfilesItemSpacingOffset(displayUUID: "UUID-A", offset: -6)

            let reloaded = ProfileManager(profilesDirectory: tmp)
            let id = try #require(reloaded.profiles.first?.id)
            let profile = try reloaded.loadProfile(id: id)
            #expect(profile.displayConfigurations["UUID-B"]?.itemSpacingOffset == 3)
        }
    }

    @Test("A global broadcast writes the template into every profile")
    func globalBroadcastWritesTheTemplate() throws {
        try withManager(seeding: [makeProfile(named: "One"), makeProfile(named: "Two")]) { manager, tmp in
            let config = DisplayIceBarConfiguration.defaultConfiguration.withItemSpacingOffset(-11)

            try manager.updateAllProfilesGlobalConfiguration(config, propagateToDisplays: false)

            let reloaded = ProfileManager(profilesDirectory: tmp)
            for meta in reloaded.profiles {
                let profile = try reloaded.loadProfile(id: meta.id)
                #expect(profile.globalDisplayConfiguration == config, "\(meta.name)")
            }
        }
    }

    @Test("Without propagation, per-display entries keep their own values")
    func globalBroadcastLeavesDisplaysAloneWhenNotPropagating() throws {
        var seed = makeProfile(named: "One")
        seed.displayConfigurations = ["UUID-A": .defaultConfiguration.withItemSpacingOffset(3)]

        try withManager(seeding: [seed]) { manager, tmp in
            let config = DisplayIceBarConfiguration.defaultConfiguration.withItemSpacingOffset(-11)

            try manager.updateAllProfilesGlobalConfiguration(config, propagateToDisplays: false)

            let reloaded = ProfileManager(profilesDirectory: tmp)
            let id = try #require(reloaded.profiles.first?.id)
            let profile = try reloaded.loadProfile(id: id)
            #expect(profile.displayConfigurations["UUID-A"]?.itemSpacingOffset == 3)
        }
    }

    @Test("With propagation, per-display entries are overwritten too")
    func globalBroadcastOverwritesDisplaysWhenPropagating() throws {
        var seed = makeProfile(named: "One")
        seed.displayConfigurations = ["UUID-A": .defaultConfiguration.withItemSpacingOffset(3)]

        try withManager(seeding: [seed]) { manager, tmp in
            let config = DisplayIceBarConfiguration.defaultConfiguration.withItemSpacingOffset(-11)

            try manager.updateAllProfilesGlobalConfiguration(config, propagateToDisplays: true)

            let reloaded = ProfileManager(profilesDirectory: tmp)
            let id = try #require(reloaded.profiles.first?.id)
            let profile = try reloaded.loadProfile(id: id)
            #expect(profile.displayConfigurations["UUID-A"] == config)
        }
    }

    @Test("A broadcast over an empty store is a no-op")
    func broadcastOverAnEmptyStoreIsHarmless() throws {
        try withManager(seeding: []) { manager, _ in
            try manager.updateAllProfilesItemSpacingOffset(displayUUID: "UUID-A", offset: -6)
            try manager.updateAllProfilesGlobalConfiguration(.defaultConfiguration, propagateToDisplays: true)
            #expect(manager.profiles.isEmpty)
        }
    }

    // MARK: Loading

    @Test("Loading an unknown profile throws")
    func loadingAnUnknownProfileThrows() throws {
        try withManager(seeding: []) { manager, _ in
            #expect(throws: (any Error).self) {
                _ = try manager.loadProfile(id: UUID())
            }
        }
    }

    @Test("A manager over an empty directory starts with no profiles")
    func emptyDirectoryYieldsNoProfiles() throws {
        try withManager(seeding: []) { manager, _ in
            #expect(manager.profiles.isEmpty)
        }
    }

    // MARK: - Helpers

    /// Runs `body` against a `ProfileManager` pointed at a fresh temporary
    /// directory seeded with `profiles`, and removes the directory after.
    private func withManager(
        seeding profiles: [Profile],
        _ body: (ProfileManager, URL) throws -> Void
    ) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try seedManifest(with: profiles, into: tmp)
        try body(ProfileManager(profilesDirectory: tmp), tmp)
    }
}
