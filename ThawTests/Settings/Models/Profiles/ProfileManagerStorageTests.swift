//
//  ProfileManagerStorageTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Saving, editing and exporting profiles on disk. Profiles live in a throwaway
/// directory and settings in a throwaway suite, and nothing here applies a profile.
@MainActor
@Suite("Profile manager storage", .serialized, .scratchDefaults)
struct ProfileManagerStorageTests {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func manifest(in directory: URL) throws -> [ProfileMetadata] {
        let data = try Data(contentsOf: directory.appendingPathComponent("profiles.json"))
        return try decoder.decode([ProfileMetadata].self, from: data)
    }

    private static func fileExists(_ id: UUID, in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id.uuidString).json").path)
    }

    @Test("A new manager over an empty directory has no profiles and creates the directory")
    func emptyDirectory() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        #expect(manager.profiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: tmp.path))
    }

    @Test("A manifest that cannot be read loads as no profiles")
    func unreadableManifest() throws {
        let tmp = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("garbage".utf8).write(to: tmp.appendingPathComponent("profiles.json"))
        #expect(ProfileManager(profilesDirectory: tmp).profiles.isEmpty)
    }

    @Test("Saving captures the current settings and adds the profile to the manifest")
    func saveCapturesCurrentState() throws {
        try ProfileTestDirectory.withManager(seeding: []) { manager, tmp in
            let appState = AppState()
            appState.settings.general.showOnHover = !Defaults.DefaultValue.showOnHover
            appState.settings.advanced.tooltipDelay = 2.5
            appState.settings.displaySettings.confirmSpacingRelaunch = false

            let id = try manager.saveProfile(name: "Work", from: appState)

            #expect(manager.profiles.map(\.name) == ["Work"])
            #expect(try Self.manifest(in: tmp).map(\.id) == [id])
            let saved = try manager.loadProfile(id: id)
            #expect(saved.name == "Work")
            #expect(saved.generalSettings.showOnHover == !Defaults.DefaultValue.showOnHover)
            #expect(saved.advancedSettings.tooltipDelay == 2.5)
            #expect(saved.confirmSpacingRelaunch == false)
        }
    }

    @Test("Deleting removes the file and the manifest entry")
    func deleteProfile() throws {
        try ProfileTestDirectory.withManager(seeding: ["A", "B"]) { manager, tmp in
            let first = try #require(manager.profiles.first)
            try manager.deleteProfile(id: first.id)
            #expect(manager.profiles.map(\.name) == ["B"])
            #expect(!Self.fileExists(first.id, in: tmp))
            #expect(try Self.manifest(in: tmp).map(\.name) == ["B"])
        }
    }

    @Test("Deleting a profile with no file throws and keeps the manifest")
    func deleteMissingProfile() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, _ in
            #expect(throws: (any Error).self) {
                try manager.deleteProfile(id: UUID())
            }
            #expect(manager.profiles.count == 1)
        }
    }

    @Test("Renaming changes the file and the manifest but keeps the identity")
    func renameProfile() throws {
        try ProfileTestDirectory.withManager(seeding: ["Old"]) { manager, tmp in
            let meta = try #require(manager.profiles.first)
            try manager.renameProfile(id: meta.id, to: "New")
            #expect(manager.profiles.first?.name == "New")
            #expect(manager.profiles.first?.id == meta.id)
            #expect(try manager.loadProfile(id: meta.id).name == "New")
            #expect(try Self.manifest(in: tmp).first?.name == "New")
            #expect(try #require(manager.profiles.first).modifiedAt >= meta.modifiedAt)
        }
    }

    @Test("Duplicating makes a new identity with the same content and layout switches")
    func duplicateProfile() throws {
        try ProfileTestDirectory.withManager(seeding: ["Source"]) { manager, tmp in
            let source = try #require(manager.profiles.first)
            manager.setLayoutBehavior(keepsChanges: false, reappliesAtLaunch: true, forProfileID: source.id)
            var profile = try manager.loadProfile(id: source.id)
            profile.hotkeys = ["toggleHidden": Data([1, 2, 3])]
            try manager.replaceProfile(profile)

            try manager.duplicateProfile(id: source.id, newName: "Copy")

            #expect(manager.profiles.count == 2)
            let copy = try #require(manager.profiles.last)
            #expect(copy.name == "Copy")
            #expect(copy.id != source.id)
            #expect(copy.keepsLayoutChanges == false)
            #expect(copy.reappliesAtLaunch == true)
            #expect(try manager.loadProfile(id: copy.id).hotkeys == ["toggleHidden": Data([1, 2, 3])])
            #expect(Self.fileExists(copy.id, in: tmp))
        }
    }

    @Test("Exporting one profile writes a bundle carrying its associations")
    func exportProfile() throws {
        try ProfileTestDirectory.withManager(seeding: ["Desk"]) { manager, tmp in
            let meta = try #require(manager.profiles.first)
            manager.setAssociatedDisplay(uuid: "DISPLAY-1", displayName: "Studio", forProfileID: meta.id)
            manager.setAssociatedSpace(key: "space-1", spaceName: "Desktop 1", forProfileID: meta.id)
            manager.setLayoutBehavior(keepsChanges: true, forProfileID: meta.id)
            let url = tmp.appendingPathComponent("export.json")

            try manager.exportProfile(id: meta.id, to: url)

            let bundle = try Self.decoder.decode(ProfileExportBundle.self, from: Data(contentsOf: url))
            let entry = try #require(bundle.entries.first)
            #expect(bundle.entries.count == 1)
            #expect(entry.profile.id == meta.id)
            #expect(entry.associatedDisplayUUID == "DISPLAY-1")
            #expect(entry.associatedDisplayName == "Studio")
            #expect(entry.associatedSpaceKey == "space-1")
            #expect(entry.associatedSpaceName == "Desktop 1")
            #expect(entry.keepsLayoutChanges == true)
            #expect(entry.reappliesAtLaunch == nil)
        }
    }

    @Test("Exporting every profile lists them all and skips ones whose file is gone")
    func exportAllProfiles() throws {
        try ProfileTestDirectory.withManager(seeding: ["A", "B", "C"]) { manager, tmp in
            let gone = manager.profiles[1].id
            try FileManager.default.removeItem(at: tmp.appendingPathComponent("\(gone.uuidString).json"))

            let json = try #require(manager.exportAllProfiles())
            let bundle = try Self.decoder.decode(ProfileExportBundle.self, from: Data(json.utf8))
            #expect(bundle.entries.map(\.profile.name) == ["A", "C"])
            #expect(bundle.version == 1)
        }
    }

    @Test("An exported profile imports back as a new identity with its display")
    func exportThenImport() throws {
        try ProfileTestDirectory.withManager(seeding: ["Travel"]) { manager, tmp in
            let meta = try #require(manager.profiles.first)
            manager.setAssociatedDisplay(uuid: "DISPLAY-2", displayName: "Laptop", forProfileID: meta.id)
            let url = tmp.appendingPathComponent("travel.json")
            try manager.exportProfile(id: meta.id, to: url)

            try manager.importProfile(from: url)

            #expect(manager.profiles.count == 2)
            let imported = try #require(manager.profiles.last)
            #expect(imported.id != meta.id)
            #expect(imported.name == "Travel")
            #expect(imported.associatedDisplayUUID == "DISPLAY-2", "the import takes the display")
            #expect(manager.profiles.first?.associatedDisplayUUID == nil, "the original gives it up")
            #expect(try Self.manifest(in: tmp).count == 2)
        }
    }

    @Test("Restoring a deleted profile puts it back at its old place and reclaims its display")
    func restoreProfile() throws {
        try ProfileTestDirectory.withManager(seeding: ["A", "B", "C"]) { manager, _ in
            var removed = manager.profiles[1]
            let profile = try manager.loadProfile(id: removed.id)
            try manager.deleteProfile(id: removed.id)
            manager.setAssociatedDisplay(uuid: "D", displayName: "Display", forProfileID: manager.profiles[0].id)
            manager.setAssociatedSpace(key: "S", spaceName: "Space", forProfileID: manager.profiles[1].id)
            removed.associatedDisplayUUID = "D"
            removed.associatedSpaceKey = "S"

            try manager.restoreProfile(profile, metadata: removed, at: 1, wasActive: true)

            #expect(manager.profiles.map(\.name) == ["A", "B", "C"])
            #expect(manager.profiles[0].associatedDisplayUUID == nil)
            #expect(manager.profiles[2].associatedSpaceKey == nil)
            #expect(manager.profiles[1].associatedDisplayUUID == "D")
            #expect(manager.activeProfileID == removed.id)
        }
    }

    @Test("Restoring a profile that is still listed replaces its entry and clamps the index")
    func restoreExistingProfile() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, _ in
            var meta = try #require(manager.profiles.first)
            let profile = try manager.loadProfile(id: meta.id)
            meta.name = "Renamed"
            try manager.restoreProfile(profile, metadata: meta, at: 99, wasActive: false)
            #expect(manager.profiles.map(\.name) == ["Renamed"])
            #expect(manager.activeProfileID == nil)
        }
    }

    @Test("Spacing broadcasts reach every profile, seeding missing displays from the template")
    func broadcastSpacing() throws {
        try ProfileTestDirectory.withManager(seeding: ["A", "B"]) { manager, _ in
            var first = try manager.loadProfile(id: manager.profiles[0].id)
            first.displayConfigurations["DISPLAY"] = DisplayThawBarConfiguration.defaultConfiguration.withUseThawBar(true)
            try manager.replaceProfile(first)

            try manager.updateAllProfilesItemSpacingOffset(displayUUID: "DISPLAY", offset: 4)

            let a = try manager.loadProfile(id: manager.profiles[0].id)
            let b = try manager.loadProfile(id: manager.profiles[1].id)
            #expect(a.displayConfigurations["DISPLAY"]?.itemSpacingOffset == 4)
            #expect(a.displayConfigurations["DISPLAY"]?.useThawBar == true, "the existing entry keeps its other values")
            #expect(b.displayConfigurations["DISPLAY"]?.itemSpacingOffset == 4)
            #expect(b.displayConfigurations["DISPLAY"]?.useThawBar == b.globalDisplayConfiguration.useThawBar)
        }
    }

    @Test("Global broadcasts set the template and, when asked, every display entry")
    func broadcastGlobal() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, _ in
            let id = manager.profiles[0].id
            var profile = try manager.loadProfile(id: id)
            profile.displayConfigurations = ["X": .defaultConfiguration]
            try manager.replaceProfile(profile)
            let config = DisplayThawBarConfiguration.defaultConfiguration.withGridColumns(7)

            try manager.updateAllProfilesGlobalConfiguration(config, propagateToDisplays: false)
            #expect(try manager.loadProfile(id: id).globalDisplayConfiguration == config)
            #expect(try manager.loadProfile(id: id).displayConfigurations["X"] == .defaultConfiguration)

            try manager.updateAllProfilesGlobalConfiguration(config, propagateToDisplays: true)
            #expect(try manager.loadProfile(id: id).displayConfigurations["X"] == config)
        }
    }

    @Test("Hooks are saved per phase, and clearing both drops the automation")
    func profileHooks() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, _ in
            let id = manager.profiles[0].id
            #expect(manager.hooks(forProfileID: id).isEmpty)
            #expect(manager.hooks(forProfileID: UUID()).isEmpty, "a missing profile has no hooks")

            try manager.setHook(HookScript(path: "/bin/true"), phase: .pre, forProfileID: id)
            try manager.setHook(HookScript(path: "/bin/echo", timeoutSeconds: 2), phase: .post, forProfileID: id)
            #expect(manager.hooks(forProfileID: id).preHook?.path == "/bin/true")
            #expect(manager.hooks(forProfileID: id).postHook?.timeoutSeconds == 2)

            try manager.setHook(nil, phase: .pre, forProfileID: id)
            try manager.setHook(nil, phase: .post, forProfileID: id)
            #expect(try manager.loadProfile(id: id).automation == nil)
        }
    }

    @Test("Layout behavior changes only the switches it is given and ignores unknown profiles")
    func layoutBehavior() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, tmp in
            let id = manager.profiles[0].id
            #expect(manager.profiles[0].keepsLayoutChanges)
            #expect(!manager.profiles[0].reappliesAtLaunch)
            manager.setLayoutBehavior(reappliesAtLaunch: true, forProfileID: id)
            #expect(manager.profiles[0].keepsLayoutChangesSetting == nil)
            #expect(manager.profiles[0].reappliesAtLaunch)
            manager.setLayoutBehavior(keepsChanges: false, forProfileID: UUID())
            #expect(manager.profiles[0].keepsLayoutChanges)
            let stored = try Self.manifest(in: tmp)
            #expect(stored.first?.reappliesAtLaunchSetting == true)
        }
    }

    @Test("A Space key finds the profile that owns it")
    func profileForSpace() throws {
        try ProfileTestDirectory.withManager(seeding: ["A", "B"]) { manager, _ in
            manager.setAssociatedSpace(key: "k", spaceName: nil, forProfileID: manager.profiles[1].id)
            #expect(manager.profile(forSpaceKey: "k")?.name == "B")
            #expect(manager.profile(forSpaceKey: "other") == nil)
        }
    }

    @Test("Updating configuration only rewrites settings and keeps the layout")
    func updateConfigurationOnly() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, _ in
            let id = manager.profiles[0].id
            var profile = try manager.loadProfile(id: id)
            profile.menuBarLayout.customNames = ["com.example:item": "Example"]
            try manager.replaceProfile(profile)
            let appState = AppState()
            appState.settings.advanced.showOnHoverDelay = 1.75
            appState.settings.displaySettings.unconfirmedSpacingProfileScope = .allProfiles

            try manager.updateProfile(id: id, scope: .configurationOnly, appState: appState)

            let updated = try manager.loadProfile(id: id)
            #expect(updated.advancedSettings.showOnHoverDelay == 1.75)
            #expect(updated.unconfirmedSpacingProfileScope == .allProfiles)
            #expect(updated.menuBarLayout.customNames == ["com.example:item": "Example"])
        }
    }

    @Test("Updating everything keeps the name and identity and leaves no temporary profile")
    func updateAll() throws {
        try ProfileTestDirectory.withManager(seeding: ["Keep"]) { manager, tmp in
            let meta = manager.profiles[0]
            let appState = AppState()
            appState.settings.general.autoRehide = !Defaults.DefaultValue.autoRehide

            try manager.updateProfile(id: meta.id, scope: .all, appState: appState)

            #expect(manager.profiles.map(\.id) == [meta.id])
            #expect(manager.profiles[0].name == "Keep")
            let updated = try manager.loadProfile(id: meta.id)
            #expect(updated.name == "Keep")
            #expect(updated.createdAt == meta.createdAt)
            #expect(updated.generalSettings.autoRehide == !Defaults.DefaultValue.autoRehide)
            let files = try FileManager.default.contentsOfDirectory(atPath: tmp.path).filter { $0.hasSuffix(".json") }
            #expect(files.count == 2, "the profile and the manifest, no leftover temporary file")
        }
    }

    @Test("Updating a profile that is not listed does nothing")
    func updateUnknown() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, _ in
            try manager.updateProfileWithCurrentState(id: UUID(), appState: AppState())
            #expect(manager.profiles.map(\.name) == ["A"])
        }
    }

    @Test("Updating only the layout keeps the groups the profile already had")
    func updateLayoutOnly() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, _ in
            let id = manager.profiles[0].id
            let appState = AppState()
            try manager.updateProfile(id: id, scope: .layoutOnly, appState: appState)
            let updated = try manager.loadProfile(id: id)
            #expect(updated.menuBarLayout.itemGroups != nil)
            #expect(updated.menuBarLayout.newItemsPlacement == appState.itemManager.newItemsPlacement)
        }
    }

    @Test("Only fresh layout updates to the active profile rearm the live layout")
    func rearmRule() {
        let id = UUID()
        #expect(ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: id, scope: .all))
        #expect(ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: id, scope: .layoutOnly))
        #expect(!ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: id, scope: .configurationOnly))
        #expect(!ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: UUID(), scope: .all))
        #expect(!ProfileManager.shouldRearmActiveLayout(updatedID: id, activeID: nil, scope: .layoutOnly))
    }

    @Test("The current layout snapshot carries the item manager's placement")
    func currentLayoutSnapshot() throws {
        try ProfileTestDirectory.withManager(seeding: []) { manager, _ in
            let appState = AppState()
            let snapshot = manager.currentLayoutSnapshot(from: appState)
            #expect(snapshot.newItemsPlacement == appState.itemManager.newItemsPlacement)
            #expect(snapshot.itemGroups == appState.itemGroupManager.snapshot())
            for (section, uids) in snapshot.itemOrder ?? [:] {
                for uid in uids {
                    #expect(snapshot.itemSectionMap?[uid] == section)
                }
            }
        }
    }

    @Test("Reapplying with no app state or no active profile does nothing")
    func reapplyWithoutState() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, _ in
            manager.reapplyActiveProfile()
            #expect(manager.layoutTask == nil)
        }
    }

    @Test("A Focus Filter request for the active profile only marks the filter active")
    func focusFilterForActiveProfile() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: ["A"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        let id = try #require(manager.profiles.first?.id)
        manager.activeProfileID = id

        await manager.applyFocusFilterProfile(requested: nil)
        #expect(!manager.focusFilterActive)
        await manager.applyFocusFilterProfile(requested: "not a uuid")
        #expect(!manager.focusFilterActive)
        await manager.applyFocusFilterProfile(requested: id.uuidString)
        #expect(manager.focusFilterActive)
        #expect(manager.layoutTask == nil)
    }

    @Test("A Focus Filter request for another profile does nothing without app state")
    func focusFilterWithoutAppState() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: ["A"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        await manager.applyFocusFilterProfile(requested: UUID().uuidString)
        #expect(manager.activeProfileID == nil)
        #expect(!manager.focusFilterActive)
    }
}
