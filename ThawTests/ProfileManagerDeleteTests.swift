//
//  ProfileManagerDeleteTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

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
@MainActor
final class ProfileManagerDeleteTests: XCTestCase {
    private var tmp: URL!

    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        tmp = nil
        super.tearDown()
    }

    /// The regression: the profile's JSON file is deleted behind the
    /// manager's back (simulating out-of-band removal), then
    /// `deleteProfile(id:)` is called. It must not throw, and the manifest
    /// entry must be gone afterward.
    func testDeleteProfileWithMissingFileDoesNotThrowAndRemovesManifestEntry() throws {
        let profile = makeProfile()
        try seedManifest(with: [profile], into: tmp)
        let profileManager = ProfileManager(profilesDirectory: tmp)
        XCTAssertTrue(profileManager.profiles.contains { $0.id == profile.id })

        // Simulate the file vanishing out-of-band before delete is called.
        try FileManager.default.removeItem(
            at: tmp.appendingPathComponent("\(profile.id.uuidString).json")
        )

        XCTAssertNoThrow(try profileManager.deleteProfile(id: profile.id))
        XCTAssertFalse(profileManager.profiles.contains { $0.id == profile.id })
    }

    /// Calling `deleteProfile(id:)` twice in a row must not throw the
    /// second time either: the file is gone after the first call, and the
    /// manifest entry with it, so the second call is a no-op deletion of an
    /// already-absent file and an already-absent entry.
    func testDeleteProfileCalledTwiceDoesNotThrowEitherTime() throws {
        let profile = makeProfile()
        try seedManifest(with: [profile], into: tmp)
        let profileManager = ProfileManager(profilesDirectory: tmp)

        XCTAssertNoThrow(try profileManager.deleteProfile(id: profile.id))
        XCTAssertNoThrow(try profileManager.deleteProfile(id: profile.id))
        XCTAssertFalse(profileManager.profiles.contains { $0.id == profile.id })
    }

    /// Happy path: the file exists on disk, `deleteProfile(id:)` removes it
    /// and the manifest entry, with no throw.
    func testDeleteProfileHappyPathRemovesFileAndManifestEntry() throws {
        let profile = makeProfile()
        try seedManifest(with: [profile], into: tmp)
        let profileManager = ProfileManager(profilesDirectory: tmp)
        let fileURL = tmp.appendingPathComponent("\(profile.id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        XCTAssertNoThrow(try profileManager.deleteProfile(id: profile.id))

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(profileManager.profiles.contains { $0.id == profile.id })
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
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

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
