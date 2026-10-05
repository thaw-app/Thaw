//
//  MenuBarHistoryRemovalTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Menu bar history removal")
struct MenuBarHistoryRemovalTests {
    @Test("Cleanup removes history without changing layout or hiding assignments")
    func clearsOnlyRetiredHistory() throws {
        let suiteName = "MenuBarHistoryRemovalTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "EnableBarHygieneAudit")
        defaults.set(Data("history".utf8), forKey: "MenuBarHygieneLedger")
        defaults.set(Date.now, forKey: "LayoutSuggestions.dismissed.unusedItems")
        let order = ["hidden": ["com.example.app:Item"]]
        let bundleMap = ["com.example.app:Item": "com.example.app"]
        let dismissedAt = Date(timeIntervalSinceReferenceDate: 1000)
        defaults.set(order, forKey: "MenuBarItemManager.savedSectionOrder")
        defaults.set(bundleMap, forKey: "MenuBarConcealBundleIDMap")
        defaults.set(dismissedAt, forKey: "LayoutSuggestions.dismissed.itemsBehindNotch")

        let migration = MigrationManager()
        for _ in 0 ..< 2 {
            migration.removeMenuBarHistory(from: defaults)
            #expect(defaults.object(forKey: "EnableBarHygieneAudit") == nil)
            #expect(defaults.object(forKey: "MenuBarHygieneLedger") == nil)
            #expect(defaults.object(forKey: "LayoutSuggestions.dismissed.unusedItems") == nil)
            #expect(defaults.dictionary(forKey: "MenuBarItemManager.savedSectionOrder") as? [String: [String]] == order)
            #expect(defaults.dictionary(forKey: "MenuBarConcealBundleIDMap") as? [String: String] == bundleMap)
            #expect(defaults.object(forKey: "LayoutSuggestions.dismissed.itemsBehindNotch") as? Date == dismissedAt)
        }
    }

    @Test("History is no longer searchable or writable through settings URLs")
    func retiredSettingIsNotExposed() {
        #expect(!SearchIndex.entries.contains { $0.property == .advanced("enableBarHygieneAudit") })
        #expect(SettingsURIHandler.keyTable["enableBarHygieneAudit"] == nil)
    }
}
