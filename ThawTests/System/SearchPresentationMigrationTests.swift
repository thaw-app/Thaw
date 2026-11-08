//
//  SearchPresentationMigrationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Search style migration")
struct SearchPresentationMigrationTests {
    @Test("A saved style is stored as the layout it opens as, and runs again harmlessly", arguments: [
        ("inspector", "extended"),
        ("assisted", "extended"),
        ("launcher", "compact"),
        ("compact", "compact"),
        ("extended", "extended"),
    ])
    func storesTheLayout(stored: String, layout: String) throws {
        let suiteName = ScratchDefaults.name("SearchPresentationMigrationTests")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { ScratchDefaults.remove(suiteName) }
        defaults.set(stored, forKey: Defaults.Key.menuBarSearchPresentation.rawValue)

        for _ in 0 ..< 2 {
            MigrationManager().migrateSearchPresentation(in: defaults)
            #expect(defaults.string(forKey: Defaults.Key.menuBarSearchPresentation.rawValue) == layout)
        }
    }

    @Test("An unknown or missing style is left alone")
    func leavesTheRest() throws {
        let suiteName = ScratchDefaults.name("SearchPresentationMigrationTests")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { ScratchDefaults.remove(suiteName) }

        MigrationManager().migrateSearchPresentation(in: defaults)
        // Registered defaults apply to every store, so check what was written.
        #expect(defaults.persistentDomain(forName: suiteName)?[Defaults.Key.menuBarSearchPresentation.rawValue] == nil)

        defaults.set("spotlight", forKey: Defaults.Key.menuBarSearchPresentation.rawValue)
        MigrationManager().migrateSearchPresentation(in: defaults)
        #expect(defaults.string(forKey: Defaults.Key.menuBarSearchPresentation.rawValue) == "spotlight")
    }

    @Test("Detailed's saved frames go, other keys stay")
    func dropsSavedFrames() throws {
        let suiteName = ScratchDefaults.name("SearchPresentationMigrationTests")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { ScratchDefaults.remove(suiteName) }
        defaults.set(["X": 1], forKey: "MenuBarSearchPanelFrame_5B639876")
        defaults.set(["X": 2], forKey: "MenuBarSearchPanelFrame_DEAD0DA7")
        defaults.set(true, forKey: "RememberSearchQuery")

        MigrationManager().migrateSearchPresentation(in: defaults)
        #expect(defaults.object(forKey: "MenuBarSearchPanelFrame_5B639876") == nil)
        #expect(defaults.object(forKey: "MenuBarSearchPanelFrame_DEAD0DA7") == nil)
        #expect(defaults.bool(forKey: "RememberSearchQuery"))
    }
}
