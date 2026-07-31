//
//  DisplaySettingsManagerGlobalFallbackTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Display settings global fallback", .serialized)
final class DisplaySettingsManagerGlobalFallbackTests {
    /// Keys `DisplaySettingsManager` persists through the `didSet` observers
    /// that `makeManager` trips. `Defaults` is hardcoded to
    /// `UserDefaults.standard`, so without this the suite would overwrite the
    /// developer's own display settings.
    private static let touchedKeys: [Defaults.Key] = [
        .globalDisplayConfiguration,
        .displayIceBarConfigurations,
    ]

    private let savedDefaults: [Defaults.Key: Data?]

    private let global = DisplayIceBarConfiguration
        .defaultConfiguration
        .withItemSpacingOffset(-16)

    init() {
        savedDefaults = Dictionary(
            uniqueKeysWithValues: Self.touchedKeys.map { ($0, Defaults.data(forKey: $0)) }
        )
    }

    deinit {
        for (key, value) in savedDefaults {
            if let value {
                Defaults.set(value, forKey: key)
            } else {
                Defaults.removeObject(forKey: key)
            }
        }
    }

    private func makeManager(
        configurations: [String: DisplayIceBarConfiguration] = [:],
        globalConfiguration: DisplayIceBarConfiguration? = nil
    ) -> DisplaySettingsManager {
        let manager = DisplaySettingsManager()
        manager.globalConfiguration = globalConfiguration ?? global
        manager.configurations = configurations
        return manager
    }

    @Test("An unresolvable display inherits the global configuration")
    func unresolvableDisplayFallsBackToGlobalConfiguration() {
        let resolved = makeManager().configuration(for: 0)

        #expect(resolved == global)
        #expect(resolved.itemSpacingOffset == -16)
    }

    @Test("A resolved display uses its explicit configuration")
    func resolvedDisplayUsesExplicitConfiguration() throws {
        let displayID = CGMainDisplayID()
        let uuid = try #require(Bridging.getDisplayUUIDString(for: displayID))
        let explicit = DisplayIceBarConfiguration
            .defaultConfiguration
            .withItemSpacingOffset(11)
        let manager = makeManager(configurations: [uuid: explicit])

        #expect(manager.configuration(for: displayID) == explicit)
    }

    @Test("A resolved display without an override inherits the global configuration")
    func resolvedDisplayWithoutOverrideFallsBackToGlobalConfiguration() throws {
        let displayID = CGMainDisplayID()
        _ = try #require(Bridging.getDisplayUUIDString(for: displayID))

        #expect(makeManager().configuration(for: displayID) == global)
    }

    @Test("The active display without an override inherits the global configuration")
    func activeDisplayWithoutOverrideFallsBackToGlobalConfiguration() {
        #expect(makeManager().configurationForActiveDisplay() == global)
    }

    @Test("The active display uses its explicit configuration")
    func activeDisplayUsesExplicitConfiguration() throws {
        let uuid = try #require(Bridging.getActiveMenuBarDisplayUUID())
        let explicit = DisplayIceBarConfiguration
            .defaultConfiguration
            .withItemSpacingOffset(9)
        let manager = makeManager(configurations: [uuid: explicit])

        #expect(manager.configurationForActiveDisplay() == explicit)
    }

    @Test("A UUID lookup uses its explicit configuration")
    func uuidLookupUsesExplicitConfiguration() {
        let explicit = DisplayIceBarConfiguration
            .defaultConfiguration
            .withItemSpacingOffset(8)
        let manager = makeManager(configurations: ["UUID-A": explicit])

        #expect(manager.configuration(forUUID: "UUID-A") == explicit)
    }

    @Test("A missing UUID inherits the global configuration")
    func uuidLookupWithoutOverrideFallsBackToGlobalConfiguration() {
        #expect(makeManager().configuration(forUUID: "UUID-MISSING") == global)
    }

    @Test("The default global configuration preserves the previous fallback")
    func defaultGlobalConfigurationPreservesPreviousFallback() {
        let manager = makeManager(globalConfiguration: .defaultConfiguration)

        #expect(
            manager.configuration(forUUID: "UUID-MISSING") == .defaultConfiguration
        )
    }
}
