//
//  ProfileManagerPersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the parts of ``ProfileManager`` that survive a process restart:
/// the on-disk manifest, the per-profile JSON files, and the menu bar
/// layout it captures out of ``Defaults``.
///
/// `ProfileManagerCRUDTests` already locks the happy paths of rename,
/// duplicate, export/import, display association, hooks and the two
/// broadcast writers, so nothing here repeats those. What is left — and
/// what these tests target — is the damaged-state and error half of the
/// same surface:
///
/// - a manifest that will not decode, or that names a profile whose file
///   is gone;
/// - a profiles directory that does not exist yet, or whose path is
///   occupied by a regular file;
/// - the load-all-before-writing-any shape of the two broadcast writers,
///   which is only observable when one profile in the middle of the batch
///   fails to load;
/// - ``ProfileManager/updateProfileLayout(id:itemManager:)``, the one
///   capture path that needs no `AppState`, and therefore the only way to
///   reach the `Defaults`-reading body of `captureCurrentLayout`;
/// - the display-clearing overload of `setAssociatedDisplay`, which
///   `ProfileManagerCRUDTests` never calls;
/// - the display-ownership reconciliation inside `importProfile`.
///
/// Every test that persists anything asserts through a *second*
/// `ProfileManager` built over the same directory, so an in-memory-only
/// change fails the test.
///
/// Deliberately out of reach: `applyProfile`, `applySnapshot`,
/// `performSetup`, `saveProfile`, `updateProfileWithCurrentState`,
/// `updateProfileConfiguration` and `rebuildProfileHotkeys` all require a
/// live `AppState` (or, for the hotkey rebuild, an `AppState` to have been
/// installed first) and cannot be driven from a unit test.
///
/// The suite is `.serialized` because `withScratchDefaults` swaps the
/// process-wide `Defaults.store`; see the constraints documented on
/// `ScratchDefaults.swift`.
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

            // The directory existing is not the point; the point is that a
            // write into it survives, which is what a freshly installed
            // copy of the app depends on.
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
        // Whole seconds: the manager encodes dates as ISO 8601, which drops
        // the fractional part, so a `Date()` would not survive a round trip
        // for an equality check.
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
