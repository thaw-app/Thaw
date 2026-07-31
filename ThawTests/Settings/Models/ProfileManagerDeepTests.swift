//
//  ProfileManagerDeepTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the ``ProfileManager`` failure paths that the existing suites step
/// around: the two `do`/`catch` blocks that swallow an I/O error rather than
/// propagating it (`ensureDirectoryExists`, `saveManifest`), and the
/// already-active short circuit in `applyFocusFilterProfile`.
///
/// `ProfileManagerPersistenceTests` reaches the *corrupt manifest* and
/// *occupied directory path* cases, but neither of those enters a catch block:
/// a file sitting at the profiles-directory path makes `fileExists` return
/// true, so `createDirectory` is never called. The cases here put a regular
/// file at a *parent* component instead, so the directory genuinely cannot be
/// created, and park a directory on the manifest path so the manifest write
/// genuinely fails.
///
/// Every failure case asserts through a *second* `ProfileManager` over the same
/// directory. That reload is what proves the swallowed write really failed
/// rather than quietly succeeding — an in-memory assertion alone would pass
/// either way.
///
/// Deliberate gaps, all of which need a live `AppState` that tests cannot
/// stand up: `performSetup(with:)`, `saveProfile(name:from:)`,
/// `applyProfile(_:to:previousProfileID:)` and its layout task,
/// `applySnapshot(_:to:)`, `updateProfileWithCurrentState(id:appState:)`,
/// `updateProfile(id:scope:appState:)`, `updateProfileConfiguration(id:appState:)`,
/// `applyCurrentConfiguration(to:from:)`, `rebuildProfileHotkeys()` past its
/// `appState` guard, `checkDisplayAndAutoSwitch()`,
/// `handleFocusFilterDeactivated()`, `applyProfileForDisplay(uuid:)`, and the
/// bodies of `reapplyActiveProfile()` and `applyFocusFilterProfile()` that run
/// once an app state exists. `captureCurrentLayout`'s item-section inversion is
/// unreachable too, for a different reason: it iterates
/// `MenuBarItemManager.computeSectionOrder(from:)`, whose two inputs
/// (`itemCache` and `savedSectionOrder`) are both private and only populated by
/// that manager's own `performSetup(with:)`.
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

            // `deleteProfile` swallows only `CocoaError.fileNoSuchFile`, on the
            // grounds that an already-absent file means the work is done. Here
            // the *parent* is not a directory, so removal fails with
            // `NSFileWriteUnknownError` (512) instead and the error propagates.
            //
            // Worth pinning: the distinction is what stops a genuinely broken
            // profiles directory from being reported to the caller as a
            // successful delete.
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

            // In memory the association took, because the association lives
            // only in the manifest there is nowhere else for it to land.
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

    /// The already-active short circuit has no observable side effect that a
    /// test without an `AppState` can read back: it flips the private
    /// `focusFilterActive` flag, which is only consumed by the two private
    /// auto-switch entry points. What is assertable is that a repeat request
    /// must not disturb the active profile or schedule a second layout pass —
    /// the profile is already applied, and re-applying it would churn every
    /// menu bar item for nothing.
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
    /// This is the case `ProfileManagerPersistenceTests` cannot produce: it
    /// occupies the profiles-directory path itself, which makes `fileExists`
    /// answer true and skips the creation attempt entirely. Blocking a parent
    /// instead leaves `fileExists` false and drives the failure into the catch.
    /// It also fails identically for a root-run test host, unlike a
    /// permissions-based block.
    private func makeUncreatableDirectoryURL(in directory: URL) throws -> URL {
        let blocker = directory.appendingPathComponent("occupied", isDirectory: false)
        try Data("not a directory".utf8).write(to: blocker, options: .atomic)
        return blocker.appendingPathComponent("Profiles", isDirectory: true)
    }

    /// Replaces `profiles.json` with a non-empty directory, so every later
    /// manifest write fails: an atomic write renames its scratch file onto the
    /// destination, and a file can never be renamed over a directory.
    ///
    /// Returns the sentinel inside that directory. Asserting the sentinel
    /// survives proves the failed write left the occupied path alone rather
    /// than clearing it out of the way.
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

    /// Writes each profile's JSON plus a `profiles.json` manifest, so a freshly
    /// constructed `ProfileManager` loads them the way it would in production.
    private func seedManifest(with profiles: [Profile], into directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = makeEncoder()

        for profile in profiles {
            let data = try encoder.encode(profile)
            try data.write(to: profileURL(for: profile.id, in: directory), options: .atomic)
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

    /// Mirrors the encoder `ProfileManager` builds in its own initializer, so
    /// seeded files decode through the manager's decoder.
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func makeProfile(named name: String) -> Profile {
        let content = ProfileContent(
            generalSettings: GeneralSettingsSnapshot(
                showIceIcon: true,
                iceIcon: .defaultIceIcon,
                lastCustomIceIcon: nil,
                customIceIconIsTemplate: true,
                useIceBar: false,
                useIceBarOnlyOnNotchedDisplay: false,
                iceBarLocation: .dynamic,
                iceBarLocationOnHotkey: false,
                showOnClick: true,
                showOnDoubleClick: false,
                showOnHover: false,
                showOnScroll: false,
                autoRehide: true,
                rehideStrategyRawValue: 0,
                rehideInterval: 15
            ),
            advancedSettings: AdvancedSettingsSnapshot(
                enableAlwaysHiddenSection: true,
                showAllSectionsOnUserDrag: true,
                sectionDividerStyle: 0,
                hideApplicationMenus: false,
                enableSecondaryContextMenu: true,
                enableSecondaryContextMenuQuit: false,
                showOnHoverDelay: 0.2,
                tooltipDelay: 1.0,
                showMenuBarTooltips: true,
                iconRefreshInterval: 3.0,
                enableDiagnosticLogging: false,
                useDoubleClickToShowAlwaysHiddenSection: false,
                useOptionClickToShowAlwaysHiddenSection: false,
                useLCSSortingOnNotchedDisplays: false,
                enableMenuBarItemOverflow: false,
                searchSectionOrder: ["visible", "hidden", "alwaysHidden"],
                searchIncludeVisible: true,
                searchIncludeHidden: true,
                searchIncludeAlwaysHidden: true
            ),
            hotkeys: [:],
            displayConfigurations: [:],
            appearanceConfiguration: .defaultConfiguration,
            menuBarLayout: MenuBarLayoutSnapshot(
                savedSectionOrder: [:],
                pinnedHiddenBundleIDs: [],
                pinnedAlwaysHiddenBundleIDs: [],
                customNames: [:]
            )
        )
        return Profile(name: name, content: content)
    }
}
