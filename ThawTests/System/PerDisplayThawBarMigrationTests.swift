//
//  PerDisplayThawBarMigrationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

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
