//
//  MigrationManagerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Settings migrations")
struct MigrationManagerTests {
    private let suites = ScratchSuites(prefix: "MigrationManagerTests")

    // MARK: Search style

    @Test("A saved search style is stored as the layout it opens as, and runs again harmlessly", arguments: [
        ("inspector", "extended"),
        ("assisted", "extended"),
        ("launcher", "compact"),
        ("compact", "compact"),
        ("extended", "extended"),
    ])
    func storesTheSearchLayout(stored: String, layout: String) throws {
        let defaults = try #require(suites.make())
        defaults.set(stored, forKey: Defaults.Key.menuBarSearchPresentation.rawValue)

        for _ in 0 ..< 2 {
            MigrationManager().migrateSearchPresentation(in: defaults)
            #expect(defaults.string(forKey: Defaults.Key.menuBarSearchPresentation.rawValue) == layout)
        }
    }

    @Test("An unknown or missing search style is left alone")
    func leavesOtherSearchStyles() throws {
        let (defaults, name) = try suites.makeNamed()

        MigrationManager().migrateSearchPresentation(in: defaults)
        // Registered defaults apply to every store, so check what was written.
        #expect(defaults.persistentDomain(forName: name)?[Defaults.Key.menuBarSearchPresentation.rawValue] == nil)

        defaults.set("spotlight", forKey: Defaults.Key.menuBarSearchPresentation.rawValue)
        MigrationManager().migrateSearchPresentation(in: defaults)
        #expect(defaults.string(forKey: Defaults.Key.menuBarSearchPresentation.rawValue) == "spotlight")
    }

    @Test("Detailed search's saved frames go, other keys stay")
    func dropsSavedSearchFrames() throws {
        let defaults = try #require(suites.make())
        defaults.set(["X": 1], forKey: "MenuBarSearchPanelFrame_5B639876")
        defaults.set(["X": 2], forKey: "MenuBarSearchPanelFrame_DEAD0DA7")
        defaults.set(true, forKey: "RememberSearchQuery")

        MigrationManager().migrateSearchPresentation(in: defaults)
        #expect(defaults.object(forKey: "MenuBarSearchPanelFrame_5B639876") == nil)
        #expect(defaults.object(forKey: "MenuBarSearchPanelFrame_DEAD0DA7") == nil)
        #expect(defaults.bool(forKey: "RememberSearchQuery"))
    }

    // MARK: Last settings page

    @Test("A saved retired settings page is stored as the page it opens, and runs again harmlessly", arguments: [
        ("Spaces", "Displays"),
        ("Automation", "Triggers"),
        ("The Lab", "General"),
        ("Advanced", "Menu Bar Layout"),
        ("Visibility", "Visibility"),
        ("Nowhere", "Nowhere"),
    ])
    func storesTheNewSettingsPage(stored: String, page: String) throws {
        let defaults = try #require(suites.make())
        defaults.set(stored, forKey: Defaults.Key.lastSettingsPane.rawValue)

        for _ in 0 ..< 2 {
            MigrationManager().migrateLastSettingsPane(in: defaults)
            #expect(defaults.string(forKey: Defaults.Key.lastSettingsPane.rawValue) == page)
        }
    }

    // MARK: Recording alerts

    @Test("A recording alerts switch saved while the alerts were hidden is cleared once, and a later choice is kept")
    func clearsRecordingAlertsOnce() throws {
        let (defaults, name) = try suites.makeNamed()
        let key = Defaults.Key.enableRecordingWatch.rawValue
        defaults.set(true, forKey: key)

        MigrationManager().resetRecordingAlertsOnReturn(in: defaults)
        #expect(defaults.persistentDomain(forName: name)?[key] == nil)

        defaults.set(true, forKey: key)
        MigrationManager().resetRecordingAlertsOnReturn(in: defaults)
        #expect(defaults.bool(forKey: key))
    }

    // MARK: Retired data

    @Test("Removing menu bar history keeps the layout and hiding assignments")
    func clearsOnlyRetiredHistory() throws {
        let defaults = try #require(suites.make())
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

    @Test("Old AX bridge logs are removed and other logs are kept")
    func removesOnlyAXBridgeLogs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-ax-bridge-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = ["ax-bridge-ABC-0.txt", "ax-bridge-ABC-1.txt", "thaw_2026-10-04_10-00-00.log", "notes.txt"]
        for name in names {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }

        MigrationManager().removeAXBridgeLogs(in: directory)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(remaining == ["notes.txt", "thaw_2026-10-04_10-00-00.log"])
    }

    @Test("A missing AX bridge log folder is not an error")
    func toleratesAMissingLogFolder() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thaw-ax-bridge-missing-\(UUID().uuidString)", isDirectory: true)
        MigrationManager().removeAXBridgeLogs(in: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

/// The one-time move from the global Thaw Bar switches to a configuration per display, against a scratch store.
@MainActor
@Suite("Per-display Thaw Bar migration", .scratchDefaults)
struct PerDisplayThawBarMigrationTests {
    private func storedConfigurations() throws -> [String: DisplayThawBarConfiguration]? {
        try Defaults.data(forKey: .displayThawBarConfigurations).map {
            try JSONDecoder().decode([String: DisplayThawBarConfiguration].self, from: $0)
        }
    }

    private func isSuccess(_ result: MigrationManager.MigrationResult) -> Bool {
        if case .success = result { true } else { false }
    }

    @Test("A Thaw Bar that was off is marked migrated and gets no configurations")
    func disabledThawBarWritesNothing() throws {
        Defaults.set(false, forKey: .useThawBar)

        #expect(isSuccess(MigrationManager().migratePerDisplayThawBar()))

        #expect(Defaults.bool(forKey: .hasMigratedPerDisplayThawBar))
        #expect(try storedConfigurations() == nil)
    }

    @Test("A Thaw Bar that was on gets one configuration per display with the old location")
    func enabledThawBarIsCarriedOver() throws {
        Defaults.set(true, forKey: .useThawBar)
        Defaults.set(false, forKey: .useThawBarOnlyOnNotchedDisplay)
        Defaults.set(ThawBarLocation.leftAligned.rawValue, forKey: .thawBarLocation)

        #expect(isSuccess(MigrationManager().migratePerDisplayThawBar()))

        #expect(Defaults.bool(forKey: .hasMigratedPerDisplayThawBar))
        let configurations = try #require(try storedConfigurations())
        #expect(configurations == DisplayThawBarConfiguration.buildConfigurations(onlyOnNotched: false, location: .leftAligned))
        #expect(configurations.values.allSatisfy { $0.useThawBar && $0.thawBarLocation == .leftAligned })
    }

    @Test("A stored location this version doesn't know becomes the dynamic location")
    func unknownLocationIsDynamic() throws {
        Defaults.set(true, forKey: .useThawBar)
        Defaults.set(true, forKey: .useThawBarOnlyOnNotchedDisplay)
        Defaults.set(99, forKey: .thawBarLocation)

        _ = MigrationManager().migratePerDisplayThawBar()

        let configurations = try #require(try storedConfigurations())
        #expect(configurations == DisplayThawBarConfiguration.buildConfigurations(onlyOnNotched: true, location: .dynamic))
    }

    @Test("Once migrated, later changes to the old switches are left alone")
    func migrationRunsOnce() throws {
        Defaults.set(true, forKey: .hasMigratedPerDisplayThawBar)
        Defaults.set(true, forKey: .useThawBar)

        #expect(isSuccess(MigrationManager().migratePerDisplayThawBar()))

        #expect(try storedConfigurations() == nil)
    }

    @Test("A failed migration names the step and the underlying error")
    func failureDescription() {
        let error = MigrationManager.MigrationError.perDisplayThawBarMigrationError(CocoaError(.coderInvalidValue))
        #expect(error.description.hasPrefix("Error migrating per-display Thaw Bar configuration: "))
        #expect(error.description.contains("NSCocoaErrorDomain"))
    }
}
