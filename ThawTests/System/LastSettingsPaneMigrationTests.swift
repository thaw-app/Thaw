//
//  LastSettingsPaneMigrationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Last settings page migration")
struct LastSettingsPaneMigrationTests {
    @Test("A saved retired page is stored as the page it opens, and runs again harmlessly", arguments: [
        ("Spaces", "Displays"),
        ("Automation", "Triggers"),
        ("The Lab", "General"),
        ("Advanced", "Menu Bar Layout"),
        ("Visibility", "Visibility"),
        ("Nowhere", "Nowhere"),
    ])
    func storesTheNewPage(stored: String, page: String) throws {
        let suiteName = ScratchDefaults.name("LastSettingsPaneMigrationTests")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { ScratchDefaults.remove(suiteName) }
        defaults.set(stored, forKey: Defaults.Key.lastSettingsPane.rawValue)

        for _ in 0 ..< 2 {
            MigrationManager().migrateLastSettingsPane(in: defaults)
            #expect(defaults.string(forKey: Defaults.Key.lastSettingsPane.rawValue) == page)
        }
    }
}
