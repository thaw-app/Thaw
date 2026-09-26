//
//  ProfileManagerPersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the parts of ``ProfileManager`` that survive a process restart:
/// the on-disk manifest, the per-profile JSON files, and the menu bar
/// layout it captures out of ``Defaults``.
///
/// `ProfileManagerCRUDTests` covers the happy paths. This suite covers the
/// damaged-state and error half:
///
/// - a manifest that won't decode, or names a profile whose file is gone;
/// - a profiles directory that doesn't exist yet, whose path is a file, or
///   whose parent is a file so it can never be created;
/// - a manifest write that fails after the profile files were written;
/// - the load-all-before-writing shape of the two broadcast writers, only
///   visible when a profile mid-batch fails to load;
/// - ``ProfileManager/updateProfileLayout(id:itemManager:)``, the only
///   capture path that needs no `AppState`;
/// - the display-clearing overload of `setAssociatedDisplay`;
/// - the display-ownership reconciliation inside `importProfile`.
///
/// Every persisting test asserts through a second `ProfileManager` over the
/// same directory, so an in-memory-only change fails. Anything that needs a
/// live `AppState` is out of reach.
///
/// `.serialized` because `withScratchDefaults` swaps the process-wide
/// `Defaults.store`.
@MainActor
@Suite("Profile manager persistence", .serialized)
struct ProfileManagerPersistenceTests {
    // MARK: - Manifest and Directory Recovery

    @Test("A manifest that will not decode loads as an empty profile list")
    func corruptManifestLoadsEmpty() throws {
        try withTemporaryDirectory { tmp in
            try Data("{ this is not a manifest".utf8).write(
                to: tmp.appendingPathComponent("profiles.json")
            )

            #expect(ProfileManager(profilesDirectory: tmp).profiles.isEmpty)
        }
    }

    @Test("A manifest entry whose profile file is gone is still listed, but fails to load")
    func manifestEntryWithoutFileIsListedButUnloadable() throws {
        let gone = makeProfile(named: "Gone")

        try withManager(seeding: [gone], omittingFilesFor: [gone.id]) { manager, _ in
            // The manifest is the list the UI renders, so the entry has to
            // survive; the failure must surface only when the profile is
            // actually opened.
            #expect(manager.profiles.map(\.id) == [gone.id])
            #expect(throws: CocoaError.self) {
                _ = try manager.loadProfile(id: gone.id)
            }
        }
    }

    @Test("A profile file holding invalid JSON fails to load with a decoding error")
    func invalidProfileJSONFailsToDecode() throws {
        try withManager(seeding: [makeProfile(named: "Desk")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            try Data("{ not json".utf8).write(
                to: tmp.appendingPathComponent("\(id.uuidString).json")
            )

            #expect(throws: DecodingError.self) {
                _ = try manager.loadProfile(id: id)
            }
        }
    }

    @Test("Exporting every profile skips the ones whose file is missing")
    func exportAllSkipsUnloadableProfiles() throws {
        let present = makeProfile(named: "PresentProfile")
        let missing = makeProfile(named: "MissingProfile")

        try withManager(
            seeding: [present, missing],
            omittingFilesFor: [missing.id]
        ) { manager, _ in
            let json = try #require(manager.exportAllProfiles())
            let bundle = try makeDecoder().decode(
                ProfileExportBundle.self,
                from: Data(json.utf8)
            )

            #expect(bundle.entries.map(\.profile.name) == ["PresentProfile"])
        }
    }

    @Test("A manager creates its profiles directory, so the first write lands on disk")
    func managerCreatesItsProfilesDirectory() throws {
        try withTemporaryDirectory { tmp in
            let nested = tmp
                .appendingPathComponent("Thaw", isDirectory: true)
                .appendingPathComponent("Profiles", isDirectory: true)
            let manager = ProfileManager(profilesDirectory: nested)

            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: nested.path,
                isDirectory: &isDirectory
            )
            #expect(exists)
            #expect(isDirectory.boolValue)

            // A write into the new directory has to survive; a fresh install
            // depends on it.
            let bundleURL = tmp.appendingPathComponent("bundle.json")
            try writeBundle(
                ProfileExportBundle(entries: [
                    ProfileExportEntry(
                        profile: makeProfile(named: "First"),
                        associatedDisplayUUID: nil,
                        associatedDisplayName: nil
                    ),
                ]),
                to: bundleURL
            )
            try manager.importProfile(from: bundleURL)

            #expect(ProfileManager(profilesDirectory: nested).profiles.count == 1)
        }
    }

    @Test("A manager whose directory path is occupied by a file starts empty instead of trapping")
    func occupiedDirectoryPathStartsEmpty() throws {
        try withTemporaryDirectory { tmp in
            let occupied = tmp.appendingPathComponent("Profiles")
            try Data("in the way".utf8).write(to: occupied)

            let manager = ProfileManager(profilesDirectory: occupied)

            #expect(manager.profiles.isEmpty)
            #expect(manager.exportAllProfiles() != nil)
        }
    }

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
            try seedManifest(with: [original], omittingFilesFor: [], into: tmp)

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
            try seedManifest(with: [doomed, kept], omittingFilesFor: [], into: tmp)

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
            try seedManifest(with: [profile], omittingFilesFor: [], into: tmp)

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
            try seedManifest(with: [profile], omittingFilesFor: [], into: tmp)

            let manager = ProfileManager(profilesDirectory: tmp)
            let sentinel = try blockManifestPath(in: tmp)

            try manager.updateAllProfilesItemSpacingOffset(displayUUID: "display-1", offset: 12)

            let reloaded = try manager.loadProfile(id: profile.id)
            #expect(reloaded.displayConfigurations["display-1"]?.itemSpacingOffset == 12)
            #expect(FileManager.default.fileExists(atPath: sentinel.path))
            #expect(ProfileManager(profilesDirectory: tmp).profiles.isEmpty)
        }
    }

    // MARK: - Broadcast Atomicity

    @Test("A spacing broadcast writes nothing when a later profile fails to load")
    func spacingBroadcastLeavesDiskUntouchedWhenAProfileIsMissing() throws {
        var kept = makeProfile(named: "Kept")
        kept.displayConfigurations = [
            "UUID-A": .defaultConfiguration.withItemSpacingOffset(3),
        ]
        let gone = makeProfile(named: "Gone")

        // `gone` is second on purpose: `kept` loads and is mutated in memory
        // before the failure, so a writer that saved as it went would have
        // already flushed it.
        try withManager(seeding: [kept, gone], omittingFilesFor: [gone.id]) { manager, tmp in
            #expect(throws: CocoaError.self) {
                try manager.updateAllProfilesItemSpacingOffset(
                    displayUUID: "UUID-A",
                    offset: -6
                )
            }

            let reloaded = try ProfileManager(profilesDirectory: tmp).loadProfile(id: kept.id)
            #expect(reloaded.displayConfigurations["UUID-A"]?.itemSpacingOffset == 3)
        }
    }

    @Test("A global broadcast writes nothing when a later profile fails to load")
    func globalBroadcastLeavesDiskUntouchedWhenAProfileIsMissing() throws {
        var kept = makeProfile(named: "Kept")
        kept.globalDisplayConfiguration = .defaultConfiguration.withItemSpacingOffset(3)
        let gone = makeProfile(named: "Gone")

        try withManager(seeding: [kept, gone], omittingFilesFor: [gone.id]) { manager, tmp in
            #expect(throws: CocoaError.self) {
                try manager.updateAllProfilesGlobalConfiguration(
                    .defaultConfiguration.withItemSpacingOffset(-11),
                    propagateToDisplays: true
                )
            }

            let reloaded = try ProfileManager(profilesDirectory: tmp).loadProfile(id: kept.id)
            #expect(reloaded.globalDisplayConfiguration.itemSpacingOffset == 3)
        }
    }

    // MARK: - Clearing a Display Association

    @Test("Clearing a display's association releases it from whichever profile held it")
    func clearingByDisplayUUIDPersists() throws {
        try withManager(seeding: [makeProfile(named: "Desk")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            manager.setAssociatedDisplay(
                uuid: "UUID-A",
                displayName: "Studio Display",
                forProfileID: id
            )

            manager.setAssociatedDisplay(uuid: nil, forDisplayUUID: "UUID-A")

            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.first?.associatedDisplayUUID == nil)
            // The cached name has to go with the UUID, otherwise the pane
            // shows a display name next to a profile that no longer claims
            // that display.
            #expect(reloaded.profiles.first?.associatedDisplayName == nil)
        }
    }

    @Test("Clearing a display nobody is associated with leaves every association intact")
    func clearingAnUnownedDisplayIsHarmless() throws {
        try withManager(seeding: [makeProfile(named: "Desk")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            manager.setAssociatedDisplay(
                uuid: "UUID-A",
                displayName: "Studio Display",
                forProfileID: id
            )

            manager.setAssociatedDisplay(uuid: nil, forDisplayUUID: "UUID-Z")

            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.first?.associatedDisplayUUID == "UUID-A")
            #expect(reloaded.profiles.first?.associatedDisplayName == "Studio Display")
        }
    }

    // MARK: - Import

    @Test("An import that claims a display takes it from the profile that held it")
    func importReconcilesDisplayOwnership() throws {
        try withManager(seeding: [makeProfile(named: "Deskbound")]) { manager, tmp in
            let existingID = try #require(manager.profiles.first?.id)
            manager.setAssociatedDisplay(
                uuid: "UUID-A",
                displayName: "Studio Display",
                forProfileID: existingID
            )

            let bundleURL = tmp.appendingPathComponent("bundle.json")
            try writeBundle(
                ProfileExportBundle(entries: [
                    ProfileExportEntry(
                        profile: makeProfile(named: "Imported"),
                        associatedDisplayUUID: "UUID-A",
                        associatedDisplayName: "Studio Display"
                    ),
                ]),
                to: bundleURL
            )

            try manager.importProfile(from: bundleURL)

            let reloaded = ProfileManager(profilesDirectory: tmp)
            let previousOwner = try #require(reloaded.profiles.first { $0.id == existingID })
            let imported = try #require(reloaded.profiles.first { $0.name == "Imported" })
            #expect(previousOwner.associatedDisplayUUID == nil)
            #expect(previousOwner.associatedDisplayName == nil)
            #expect(imported.associatedDisplayUUID == "UUID-A")
            #expect(imported.associatedDisplayName == "Studio Display")
        }
    }

    @Test("A bundle whose entries share an identifier imports as two distinct profiles")
    func importOfCollidingIdentifiersYieldsTwoProfiles() throws {
        let first = makeProfile(named: "First")
        // Same `id` as `first`: `Profile.id` is a `let`, so copying the value
        // and renaming it reproduces a bundle hand-assembled from two exports
        // of the same profile.
        var second = first
        second.name = "Second"

        try withManager(seeding: []) { manager, tmp in
            let bundleURL = tmp.appendingPathComponent("bundle.json")
            try writeBundle(
                ProfileExportBundle(entries: [
                    ProfileExportEntry(
                        profile: first,
                        associatedDisplayUUID: nil,
                        associatedDisplayName: nil
                    ),
                    ProfileExportEntry(
                        profile: second,
                        associatedDisplayUUID: nil,
                        associatedDisplayName: nil
                    ),
                ]),
                to: bundleURL
            )

            try manager.importProfile(from: bundleURL)

            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.map(\.name).sorted() == ["First", "Second"])
            #expect(Set(reloaded.profiles.map(\.id)).count == 2)
            #expect(!reloaded.profiles.contains(where: { $0.id == first.id }))
            // Two manifest entries are worthless if they point at one file.
            for meta in reloaded.profiles {
                #expect(try reloaded.loadProfile(id: meta.id).name == meta.name)
            }
        }
    }

    // MARK: - Layout Capture

    @Test("A layout update captures the stored menu bar defaults into the profile")
    func layoutUpdateCapturesTheStoredDefaults() throws {
        let uid = "com.example.one:Item-0"
        let savedSectionOrder: [String: [String]] = ["hidden": [uid]]
        let pinnedHidden = ["com.example.pinned"]
        let pinnedAlwaysHidden = ["com.example.buried"]
        let customNames: [String: String] = [uid: "Renamed"]
        let itemHotkeys: [String: Data] = [uid: Data([0x01, 0x02])]

        try withScratchDefaults { suite in
            suite.set(savedSectionOrder, forKey: "MenuBarItemManager.savedSectionOrder")
            suite.set(pinnedHidden, forKey: "MenuBarItemManager.pinnedHiddenBundleIDs")
            suite.set(pinnedAlwaysHidden, forKey: "MenuBarItemManager.pinnedAlwaysHiddenBundleIDs")
            Defaults.set(customNames, forKey: .menuBarItemCustomNames)
            Defaults.set(itemHotkeys, forKey: .menuBarItemHotkeys)

            try withManager(seeding: [makeProfile(named: "Desk")]) { manager, tmp in
                let id = try #require(manager.profiles.first?.id)

                try manager.updateProfileLayout(id: id, itemManager: MenuBarItemManager())

                let layout = try ProfileManager(profilesDirectory: tmp)
                    .loadProfile(id: id)
                    .menuBarLayout
                #expect(layout.savedSectionOrder == savedSectionOrder)
                #expect(layout.pinnedHiddenBundleIDs == pinnedHidden)
                #expect(layout.pinnedAlwaysHiddenBundleIDs == pinnedAlwaysHidden)
                #expect(layout.customNames == customNames)
                #expect(layout.itemHotkeys == itemHotkeys)
                #expect(
                    layout.newItemsPlacement == MenuBarItemManager.NewItemsPlacement.defaultValue
                )
            }
        }
    }

    @Test("A layout update over an empty store replaces the profile's stored layout")
    func layoutUpdateOverAnEmptyStoreClearsTheProfile() throws {
        var seed = makeProfile(named: "Desk")
        seed.menuBarLayout = MenuBarLayoutSnapshot(
            savedSectionOrder: ["hidden": ["com.example.one:Item-0"]],
            pinnedHiddenBundleIDs: ["com.example.pinned"],
            pinnedAlwaysHiddenBundleIDs: ["com.example.buried"],
            customNames: ["com.example.one:Item-0": "Renamed"]
        )

        try withScratchDefaults { _ in
            try withManager(seeding: [seed]) { manager, tmp in
                // The capture is a snapshot of the store, not a merge with
                // whatever the profile already held: an empty store must
                // overwrite, or a profile updated while the menu bar was torn
                // down would silently keep its stale layout.
                try manager.updateProfileLayout(id: seed.id, itemManager: MenuBarItemManager())

                let layout = try ProfileManager(profilesDirectory: tmp)
                    .loadProfile(id: seed.id)
                    .menuBarLayout
                #expect(layout.savedSectionOrder.isEmpty)
                #expect(layout.pinnedHiddenBundleIDs.isEmpty)
                #expect(layout.pinnedAlwaysHiddenBundleIDs.isEmpty)
                #expect(layout.customNames.isEmpty)
            }
        }
    }

    @Test("A layout update bumps the modification date in both the file and the manifest")
    func layoutUpdateBumpsTheModificationDateEverywhere() throws {
        var seed = makeProfile(named: "Desk")
        // Whole seconds: ISO 8601 encoding drops fractions, so a `Date()`
        // wouldn't survive a round trip.
        seed.createdAt = Date(timeIntervalSince1970: 1_000_000)
        seed.modifiedAt = Date(timeIntervalSince1970: 1_000_000)

        try withScratchDefaults { _ in
            try withManager(seeding: [seed]) { manager, tmp in
                try manager.updateProfileLayout(id: seed.id, itemManager: MenuBarItemManager())

                let reloaded = ProfileManager(profilesDirectory: tmp)
                let meta = try #require(reloaded.profiles.first)
                let file = try reloaded.loadProfile(id: seed.id)
                #expect(meta.modifiedAt > seed.modifiedAt)
                // A manifest that disagrees with the file sorts the profile
                // list by a date the profile does not actually have.
                #expect(meta.modifiedAt == file.modifiedAt)
                #expect(file.createdAt == seed.createdAt)
            }
        }
    }

    @Test("Updating the layout of an unknown profile throws")
    func layoutUpdateOfAnUnknownProfileThrows() throws {
        try withScratchDefaults { _ in
            try withManager(seeding: []) { manager, _ in
                #expect(throws: CocoaError.self) {
                    try manager.updateProfileLayout(
                        id: UUID(),
                        itemManager: MenuBarItemManager()
                    )
                }
            }
        }
    }

    // MARK: - Remaining Error Paths

    @Test("Setting a hook on a profile whose file is missing throws")
    func settingAHookOnAMissingProfileThrows() throws {
        let gone = makeProfile(named: "Gone")

        try withManager(seeding: [gone], omittingFilesFor: [gone.id]) { manager, _ in
            #expect(throws: CocoaError.self) {
                try manager.setHook(
                    HookScript(path: "/tmp/pre.sh", timeoutSeconds: 5),
                    phase: .pre,
                    forProfileID: gone.id
                )
            }
        }
    }

    @Test("Exporting an unknown profile throws")
    func exportingAnUnknownProfileThrows() throws {
        try withManager(seeding: []) { manager, tmp in
            #expect(throws: CocoaError.self) {
                try manager.exportProfile(
                    id: UUID(),
                    to: tmp.appendingPathComponent("export.json")
                )
            }
        }
    }

    @Test("Exporting into a directory that does not exist throws and leaves no file")
    func exportingIntoAMissingDirectoryThrows() throws {
        try withManager(seeding: [makeProfile(named: "Desk")]) { manager, tmp in
            let id = try #require(manager.profiles.first?.id)
            let destination = tmp
                .appendingPathComponent("no-such-directory", isDirectory: true)
                .appendingPathComponent("export.json")

            #expect(throws: CocoaError.self) {
                try manager.exportProfile(id: id, to: destination)
            }
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }
    }

    // MARK: - Inert Without an App State

    @Test("A focus filter request that was never recorded leaves the active profile alone")
    func focusFilterWithoutARequestIsIgnored() async throws {
        try await withTemporaryDirectory { tmp in
            try seedManifest(with: [], omittingFilesFor: [], into: tmp)
            let manager = ProfileManager(profilesDirectory: tmp)

            try await withScratchDefaults { _ in
                await manager.applyFocusFilterProfile()
            }

            #expect(manager.activeProfileID == nil)
            #expect(manager.layoutTask == nil)
        }
    }

    @Test("A focus filter request naming an unparsable identifier is ignored")
    func focusFilterWithAnUnparsableIdentifierIsIgnored() async throws {
        try await withTemporaryDirectory { tmp in
            try seedManifest(with: [], omittingFilesFor: [], into: tmp)
            let manager = ProfileManager(profilesDirectory: tmp)

            try await withScratchDefaults { suite in
                suite.set("not-a-uuid", forKey: "FocusFilterRequestedProfileID")
                await manager.applyFocusFilterProfile()
            }

            #expect(manager.activeProfileID == nil)
            #expect(manager.layoutTask == nil)
        }
    }

    @Test("A focus filter request cannot activate a profile before setup has run")
    func focusFilterWithoutAnAppStateActivatesNothing() async throws {
        let seed = makeProfile(named: "Focused")

        try await withTemporaryDirectory { tmp in
            try seedManifest(with: [seed], omittingFilesFor: [], into: tmp)
            let manager = ProfileManager(profilesDirectory: tmp)
            let requestedID = seed.id.uuidString

            try await withScratchDefaults { suite in
                suite.set(requestedID, forKey: "FocusFilterRequestedProfileID")
                await manager.applyFocusFilterProfile()
            }

            // Marking the profile active without ever pushing it into the app
            // would leave the UI claiming a profile that is not applied.
            #expect(manager.activeProfileID == nil)
            #expect(manager.layoutTask == nil)
        }
    }

    /// The short circuit only flips the private `focusFilterActive` flag. What
    /// is assertable: a repeat request leaves the active profile alone and
    /// schedules no second layout pass, which would churn every menu bar item.
    @Test("A focus filter request naming the already-active profile changes nothing")
    func focusFilterRequestForTheActiveProfileIsInert() async throws {
        let seed = makeProfile(named: "Focused")

        try await withTemporaryDirectory { tmp in
            try seedManifest(with: [seed], omittingFilesFor: [], into: tmp)
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
            try seedManifest(with: [seed], omittingFilesFor: [], into: tmp)
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

    @Test("Re-applying the active profile before setup has run schedules no layout work")
    func reapplyWithoutAnAppStateSchedulesNothing() throws {
        let seed = makeProfile(named: "Desk")

        try withManager(seeding: [seed]) { manager, _ in
            manager.activeProfileID = seed.id

            manager.reapplyActiveProfile()

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

    /// Runs `body` against a `ProfileManager` pointed at a fresh temporary
    /// directory seeded with `profiles`, and removes the directory after.
    ///
    /// Identifiers listed in `omitted` get a manifest entry but no JSON file,
    /// which is how a profile folder looks after an out-of-band deletion or a
    /// half-finished cloud sync.
    private func withManager(
        seeding profiles: [Profile],
        omittingFilesFor omitted: Set<UUID> = [],
        _ body: (ProfileManager, URL) throws -> Void
    ) throws {
        try withTemporaryDirectory { tmp in
            try seedManifest(with: profiles, omittingFilesFor: omitted, into: tmp)
            try body(ProfileManager(profilesDirectory: tmp), tmp)
        }
    }

    /// Writes each profile's JSON plus a `profiles.json` manifest, so a
    /// freshly constructed `ProfileManager` loads them the way it would in
    /// production.
    private func seedManifest(
        with profiles: [Profile],
        omittingFilesFor omitted: Set<UUID>,
        into directory: URL
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = makeEncoder()

        for profile in profiles where !omitted.contains(profile.id) {
            let data = try encoder.encode(profile)
            try data.write(
                to: directory.appendingPathComponent("\(profile.id.uuidString).json"),
                options: .atomic
            )
        }

        let metadata = profiles.map {
            ProfileMetadata(id: $0.id, name: $0.name, createdAt: $0.createdAt, modifiedAt: $0.modifiedAt)
        }
        let manifestData = try encoder.encode(metadata)
        try manifestData.write(
            to: directory.appendingPathComponent("profiles.json"),
            options: .atomic
        )
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

    private func writeBundle(_ bundle: ProfileExportBundle, to url: URL) throws {
        try makeEncoder().encode(bundle).write(to: url, options: .atomic)
    }

    /// Mirrors the encoder `ProfileManager` builds in its own initializer, so
    /// seeded files decode through the manager's decoder.
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
