//
//  MigrationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``MigrationManager``, which runs once at launch to bring settings
/// written by an earlier build up to the current format.
///
/// The only surviving migration converts the global Thaw Bar switches into
/// per-display configurations. It is destructive in the sense that matters: it
/// writes `displayIceBarConfigurations` and then sets a latch so it never runs
/// again. Two things therefore have to hold. The latch must be set on *every*
/// path — including the "nothing to migrate" path, otherwise the migration
/// re-runs at each launch and stomps whatever the user has since configured
/// per display. And the latch must not be set when encoding fails, so a
/// transient failure does not permanently skip the conversion.
///
/// Every case runs against a scratch defaults suite, since `migrateAll()`
/// writes through the `Defaults` facade and would otherwise mutate the
/// developer's real domain. `Defaults.store` is process-wide, so the suite is
/// serialized.
@MainActor
@Suite("Settings migration", .serialized)
struct MigrationTests {
    /// Decodes whatever the migration wrote, or nil when it wrote nothing.
    private func storedConfigurations() throws -> [String: DisplayIceBarConfiguration]? {
        guard let data = Defaults.data(forKey: .displayIceBarConfigurations) else {
            return nil
        }
        return try JSONDecoder().decode([String: DisplayIceBarConfiguration].self, from: data)
    }

    // MARK: - Latch

    @Test("A run on a fresh domain sets the migration latch")
    func freshDomainSetsTheLatch() throws {
        try withScratchDefaults { _ in
            #expect(!Defaults.bool(forKey: .hasMigratedPerDisplayIceBar))

            MigrationManager().migrateAll()

            #expect(Defaults.bool(forKey: .hasMigratedPerDisplayIceBar))
        }
    }

    /// With the Thaw Bar switched off there is nothing to convert, but the
    /// latch still has to be set — otherwise the migration reconsiders the
    /// legacy keys at every launch.
    @Test("A disabled Thaw Bar writes no configurations but still latches")
    func disabledIceBarWritesNothingButLatches() throws {
        try withScratchDefaults { _ in
            Defaults.set(false, forKey: .useIceBar)

            MigrationManager().migrateAll()

            #expect(Defaults.bool(forKey: .hasMigratedPerDisplayIceBar))
            #expect(Defaults.data(forKey: .displayIceBarConfigurations) == nil)
        }
    }

    /// Once the latch is set, the legacy keys are ignored entirely — this is
    /// what protects a user who has since edited their per-display settings.
    @Test("An already-latched domain is left untouched")
    func latchedDomainIsLeftUntouched() throws {
        try withScratchDefaults { _ in
            Defaults.set(true, forKey: .hasMigratedPerDisplayIceBar)
            Defaults.set(true, forKey: .useIceBar)

            MigrationManager().migrateAll()

            #expect(Defaults.data(forKey: .displayIceBarConfigurations) == nil)
        }
    }

    @Test("A second run does not overwrite the first run's output")
    func secondRunIsANoOp() throws {
        try withScratchDefaults { _ in
            Defaults.set(true, forKey: .useIceBar)

            MigrationManager().migrateAll()
            let afterFirstRun = Defaults.data(forKey: .displayIceBarConfigurations)

            let sentinel = Data("sentinel".utf8)
            Defaults.set(sentinel, forKey: .displayIceBarConfigurations)
            MigrationManager().migrateAll()

            #expect(afterFirstRun != nil)
            #expect(Defaults.data(forKey: .displayIceBarConfigurations) == sentinel)
        }
    }

    // MARK: - Conversion

    @Test("An enabled Thaw Bar writes a decodable configuration payload")
    func enabledIceBarWritesADecodablePayload() throws {
        try withScratchDefaults { _ in
            Defaults.set(true, forKey: .useIceBar)
            Defaults.set(IceBarLocation.rightAligned.rawValue, forKey: .iceBarLocation)

            MigrationManager().migrateAll()

            let configurations = try #require(try storedConfigurations())
            #expect(Defaults.bool(forKey: .hasMigratedPerDisplayIceBar))

            for configuration in configurations.values {
                #expect(configuration.useIceBar)
                #expect(configuration.iceBarLocation == .rightAligned)
                #expect(!configuration.alwaysShowHiddenItems)
                #expect(configuration.iceBarLayout == .horizontal)
                #expect(configuration.gridColumns == 4)
                #expect(configuration.itemSpacingOffset == 0)
            }
        }
    }

    /// A raw value the current build does not recognize — from a downgrade, or
    /// a hand-edited plist — has to resolve to `.dynamic` rather than abort the
    /// migration.
    @Test("An unrecognized location falls back to dynamic")
    func unrecognizedLocationFallsBackToDynamic() throws {
        try withScratchDefaults { _ in
            Defaults.set(true, forKey: .useIceBar)
            Defaults.set(9999, forKey: .iceBarLocation)

            MigrationManager().migrateAll()

            let configurations = try #require(try storedConfigurations())
            for configuration in configurations.values {
                #expect(configuration.iceBarLocation == .dynamic)
            }
        }
    }

    /// "Only on notched displays" is not carried across as a flag; it is
    /// resolved per display at migration time, so a machine with no notched
    /// display ends up with every configuration disabled.
    @Test("The notched-only switch is resolved per display rather than stored")
    func notchedOnlySwitchIsResolvedPerDisplay() throws {
        try withScratchDefaults { _ in
            Defaults.set(true, forKey: .useIceBar)
            Defaults.set(true, forKey: .useIceBarOnlyOnNotchedDisplay)

            MigrationManager().migrateAll()

            let configurations = try #require(try storedConfigurations())
            let expected = DisplayIceBarConfiguration.buildConfigurations(
                onlyOnNotched: true,
                location: .dynamic
            )

            #expect(configurations.keys.sorted() == expected.keys.sorted())
            for (uuid, configuration) in configurations {
                #expect(configuration.useIceBar == expected[uuid]?.useIceBar)
            }
        }
    }

    // MARK: - Errors

    @Test("A migration error describes the underlying failure")
    func migrationErrorDescribesTheUnderlyingFailure() {
        struct Underlying: Error, CustomStringConvertible {
            var description: String { "the underlying failure" }
        }

        let error = MigrationManager.MigrationError.perDisplayIceBarMigrationError(Underlying())

        #expect(error.description.contains("per-display"))
        #expect(error.description.contains("the underlying failure"))
    }
}
