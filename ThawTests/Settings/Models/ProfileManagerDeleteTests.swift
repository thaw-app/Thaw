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

    // MARK: - Helpers

    private func makeProfile() -> Profile {
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
        return Profile(name: "Delete Test", content: content)
    }

    /// Writes both the profile's JSON file and a `profiles.json` manifest
    /// listing it, so a freshly constructed `ProfileManager` loads it into
    /// `profiles` the same way it would in production.
    private func seedManifest(with profiles: [Profile], into directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for profile in profiles {
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
}
