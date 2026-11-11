//
//  SpaceAppearanceKeyMigrationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Per-Space look key migration")
struct SpaceAppearanceKeyMigrationTests {
    private let key = Defaults.Key.menuBarAppearanceSpaceOverrides.rawValue

    private func space(_ id: CGSSpaceID, _ key: String) -> Bridging.ManagedSpace {
        Bridging.ManagedSpace(spaceID: id, persistentKey: key, displayIdentifier: "D", ordinal: 1)
    }

    private func stored(_ object: [String: Any], in defaults: UserDefaults) throws {
        try defaults.set(JSONSerialization.data(withJSONObject: object), forKey: key)
    }

    private func read(_ defaults: UserDefaults) throws -> [String: Any] {
        let data = try #require(defaults.data(forKey: key))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("A raw Space ID the live list knows moves to its persistent key; running again changes nothing")
    func movesResolvedIDs() throws {
        let suiteName = ScratchDefaults.name("SpaceAppearanceKeyMigrationTests")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { ScratchDefaults.remove(suiteName) }
        try stored(["42": ["look": "red"], "77": ["look": "blue"]], in: defaults)

        for _ in 0 ..< 2 {
            MigrationManager().migrateSpaceAppearanceKeys(in: defaults, spaces: [space(42, "DESK-A")])
            let overrides = try read(defaults)
            #expect((overrides["DESK-A"] as? [String: String])?["look"] == "red")
            #expect(overrides["42"] == nil)
            #expect((overrides["77"] as? [String: String])?["look"] == "blue", "unresolved stays for a later launch")
        }
    }

    @Test("An entry already under the persistent key wins over the raw one")
    func persistentEntryWins() throws {
        let suiteName = ScratchDefaults.name("SpaceAppearanceKeyMigrationTests")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { ScratchDefaults.remove(suiteName) }
        try stored(["42": ["look": "old"], "DESK-A": ["look": "new"]], in: defaults)

        MigrationManager().migrateSpaceAppearanceKeys(in: defaults, spaces: [space(42, "DESK-A")])
        let overrides = try read(defaults)
        #expect((overrides["DESK-A"] as? [String: String])?["look"] == "new")
        #expect(overrides["42"] == nil)
    }

    @Test("Nothing stored, or nothing resolvable, is left untouched")
    func leavesTheRest() throws {
        let suiteName = ScratchDefaults.name("SpaceAppearanceKeyMigrationTests")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { ScratchDefaults.remove(suiteName) }
        MigrationManager().migrateSpaceAppearanceKeys(in: defaults, spaces: [space(42, "DESK-A")])
        #expect(defaults.persistentDomain(forName: suiteName)?[key] == nil)

        try stored(["77": ["look": "blue"]], in: defaults)
        let before = defaults.data(forKey: key)
        MigrationManager().migrateSpaceAppearanceKeys(in: defaults, spaces: [])
        #expect(defaults.data(forKey: key) == before)
    }
}

@Suite("Per-Space look lookup")
struct SpaceAppearanceLookupTests {
    private let base = MenuBarAppearanceConfigurationV2.defaultConfiguration
    private var other: MenuBarAppearanceConfigurationV2 {
        var configuration = base
        configuration.isInset.toggle()
        return configuration
    }

    @Test("The persistent key is read first, then a raw ID left from before the migration")
    func lookup() {
        typealias M = MenuBarAppearanceManager
        #expect(M.effectiveConfiguration(base: base, overrides: ["K": other], activeSpaceID: 3, activeSpaceKey: "K") == other)
        #expect(M.effectiveConfiguration(base: base, overrides: ["3": other], activeSpaceID: 3, activeSpaceKey: "K") == other)
        #expect(M.effectiveConfiguration(base: base, overrides: [:], activeSpaceID: 3, activeSpaceKey: "K") == base)
    }

    @Test("Saving with a key stores under it and drops the raw entry; without one it keeps the raw ID")
    func saving() {
        typealias M = MenuBarAppearanceManager
        let keyed = M.overrides(["3": base], setting: other, spaceID: 3, key: "K")
        #expect(keyed["K"] == other)
        #expect(keyed["3"] == nil)
        #expect(M.overrides([:], setting: other, spaceID: 3, key: nil)["3"] == other)
        #expect(M.overrides(["K": other, "3": other], setting: nil, spaceID: 3, key: "K").isEmpty)
    }
}

@MainActor
@Suite("Editing a Space's own look", .serialized, .scratchDefaults)
struct SpaceAppearanceEditingTests {
    @Test("With its own look, an edit changes that Space's look and leaves the shared one")
    func editsTheSpaceLook() {
        let manager = MenuBarAppearanceManager()
        let shared = manager.configuration
        manager.saveOverrideForActiveSpace()
        #expect(manager.activeSpaceHasOverride)

        var edited = manager.editedConfiguration
        edited.isInset.toggle()
        manager.editedConfiguration = edited
        #expect(manager.configuration == shared, "the shared look is untouched")
        #expect(manager.effectiveConfiguration == edited, "the edit shows on this Space")

        manager.removeOverrideForActiveSpace()
        #expect(manager.effectiveConfiguration == shared)
    }

    @Test("Without its own look, an edit changes the shared look")
    func editsTheSharedLook() {
        let manager = MenuBarAppearanceManager()
        var edited = manager.editedConfiguration
        edited.isInset.toggle()
        manager.editedConfiguration = edited
        #expect(manager.configuration == edited)
        #expect(!manager.activeSpaceHasOverride)
    }
}
