//
//  ProfileManagerCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the capture half of ``ProfileManager``: saving the current
/// configuration as a profile, overwriting an existing profile from current
/// state, and the scoped-update dispatcher.
///
/// These run against real stores — `AppSettings`, `MenuBarAppearanceManager`,
/// `MenuBarItemManager` — through the narrow seam
/// `saveProfile(name:settings:appearanceManager:itemManager:)`, so no live
/// `AppState` is needed. Every store is constructed and mutated inside a
/// scratch `Defaults` suite: the settings models persist through `didSet`,
/// and layout capture reads `Defaults.store` directly, so leaking either
/// would corrupt the runner's real domain.
///
/// Like the CRUD suite, mutating cases assert against a *reloaded* manager
/// wherever the persisted state is what matters.
@MainActor
@Suite("Profile manager capture", .serialized)
struct ProfileManagerCaptureTests {
    // MARK: Save

    @Test("Saving captures the live settings into a persisted profile")
    func savePersistsCurrentConfiguration() throws {
        try withScratchDefaults { _ in
            try withManager(seeding: []) { manager, tmp in
                let settings = AppSettings()
                settings.general.rehideInterval = 42
                settings.general.showOnClick = false
                settings.displaySettings.confirmSpacingRelaunch = false
                settings.displaySettings.globalConfiguration =
                    .defaultConfiguration.withItemSpacingOffset(4)

                try manager.saveProfile(
                    name: "Captured",
                    settings: settings,
                    appearanceManager: MenuBarAppearanceManager(),
                    itemManager: MenuBarItemManager()
                )

                let id = try #require(manager.profiles.first?.id)
                let saved = try manager.loadProfile(id: id)
                #expect(saved.name == "Captured")
                #expect(saved.generalSettings.rehideInterval == 42)
                #expect(saved.generalSettings.showOnClick == false)
                #expect(saved.confirmSpacingRelaunch == false)
                #expect(saved.globalDisplayConfiguration.itemSpacingOffset == 4)
                #expect(ProfileManager(profilesDirectory: tmp).profiles.count == 1)
            }
        }
    }

    @Test("Saving appends to existing profiles instead of replacing them")
    func saveAppendsToManifest() throws {
        try withScratchDefaults { _ in
            try withManager(seeding: [makeProfile(named: "Existing")]) { manager, tmp in
                try manager.saveProfile(
                    name: "Second",
                    settings: AppSettings(),
                    appearanceManager: MenuBarAppearanceManager(),
                    itemManager: MenuBarItemManager()
                )

                #expect(manager.profiles.map(\.name) == ["Existing", "Second"])
                #expect(ProfileManager(profilesDirectory: tmp).profiles.count == 2)
            }
        }
    }

    // MARK: Update With Current State

    @Test("Updating with current state keeps identity and refreshes content")
    func updateKeepsIdentityAndRefreshesContent() throws {
        try withScratchDefaults { _ in
            try withManager(seeding: [makeProfile(named: "Original")]) { manager, tmp in
                let original = try #require(manager.profiles.first)
                let settings = AppSettings()
                settings.general.rehideInterval = 99

                try manager.updateProfileWithCurrentState(
                    id: original.id,
                    settings: settings,
                    appearanceManager: MenuBarAppearanceManager(),
                    itemManager: MenuBarItemManager()
                )

                let updated = try manager.loadProfile(id: original.id)
                #expect(updated.id == original.id)
                #expect(updated.name == "Original")
                #expect(updated.createdAt == original.createdAt)
                #expect(updated.generalSettings.rehideInterval == 99)

                let reloaded = ProfileManager(profilesDirectory: tmp)
                #expect(reloaded.profiles.count == 1)
                #expect(reloaded.profiles.first?.name == "Original")
            }
        }
    }

    @Test("Updating with current state leaves no temp profile behind")
    func updateCleansUpTempProfile() throws {
        try withScratchDefaults { _ in
            try withManager(seeding: [makeProfile(named: "Original")]) { manager, tmp in
                let id = try #require(manager.profiles.first?.id)

                try manager.updateProfileWithCurrentState(
                    id: id,
                    settings: AppSettings(),
                    appearanceManager: MenuBarAppearanceManager(),
                    itemManager: MenuBarItemManager()
                )

                #expect(!manager.profiles.contains { $0.name == "__temp_update__" })
                // Exactly the profile's JSON and the manifest survive.
                let files = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
                #expect(files.sorted() == ["\(id.uuidString).json", "profiles.json"])
            }
        }
    }

    @Test("Updating an unknown profile is a no-op")
    func updatingAnUnknownProfileDoesNothing() throws {
        try withScratchDefaults { _ in
            try withManager(seeding: []) { manager, tmp in
                try manager.updateProfileWithCurrentState(
                    id: UUID(),
                    settings: AppSettings(),
                    appearanceManager: MenuBarAppearanceManager(),
                    itemManager: MenuBarItemManager()
                )

                #expect(manager.profiles.isEmpty)
                #expect(try FileManager.default
                    .contentsOfDirectory(atPath: tmp.path) == ["profiles.json"])
            }
        }
    }

    // MARK: Scoped Updates

    @Test("The .configurationOnly scope refreshes settings but not the layout")
    func configurationOnlyLeavesLayoutAlone() throws {
        try withScratchDefaults { _ in
            let seeded = makeProfile(
                named: "Scoped",
                savedSectionOrder: ["hidden": ["a", "b"]]
            )
            try withManager(seeding: [seeded]) { manager, _ in
                let settings = AppSettings()
                settings.general.rehideInterval = 7

                try manager.updateProfile(
                    id: seeded.id,
                    scope: .configurationOnly,
                    settings: settings,
                    appearanceManager: MenuBarAppearanceManager(),
                    itemManager: MenuBarItemManager()
                )

                let updated = try manager.loadProfile(id: seeded.id)
                #expect(updated.generalSettings.rehideInterval == 7)
                #expect(updated.menuBarLayout.savedSectionOrder == ["hidden": ["a", "b"]])
            }
        }
    }

    @Test("The .layoutOnly scope recaptures the layout but not the settings")
    func layoutOnlyLeavesConfigurationAlone() throws {
        try withScratchDefaults { _ in
            let seeded = makeProfile(
                named: "Scoped",
                savedSectionOrder: ["hidden": ["a", "b"]]
            )
            try withManager(seeding: [seeded]) { manager, _ in
                let settings = AppSettings()
                settings.general.rehideInterval = 7

                try manager.updateProfile(
                    id: seeded.id,
                    scope: .layoutOnly,
                    settings: settings,
                    appearanceManager: MenuBarAppearanceManager(),
                    itemManager: MenuBarItemManager()
                )

                let updated = try manager.loadProfile(id: seeded.id)
                // The fixture value survives; the live settings do not land.
                #expect(updated.generalSettings.rehideInterval == 15)
                // Recaptured from the scratch store and an empty item cache.
                #expect(updated.menuBarLayout.savedSectionOrder.isEmpty)
            }
        }
    }

    @Test("The .all scope refreshes settings and layout together")
    func allScopeRefreshesEverything() throws {
        try withScratchDefaults { _ in
            let seeded = makeProfile(
                named: "Scoped",
                savedSectionOrder: ["hidden": ["a", "b"]]
            )
            try withManager(seeding: [seeded]) { manager, _ in
                let settings = AppSettings()
                settings.general.rehideInterval = 7

                try manager.updateProfile(
                    id: seeded.id,
                    scope: .all,
                    settings: settings,
                    appearanceManager: MenuBarAppearanceManager(),
                    itemManager: MenuBarItemManager()
                )

                let updated = try manager.loadProfile(id: seeded.id)
                #expect(updated.generalSettings.rehideInterval == 7)
                #expect(updated.menuBarLayout.savedSectionOrder.isEmpty)
            }
        }
    }

    // MARK: Helpers

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
