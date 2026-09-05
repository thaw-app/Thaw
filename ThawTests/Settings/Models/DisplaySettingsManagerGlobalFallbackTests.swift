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

/// Covers the read side of ``DisplaySettingsManager``'s inheritance rule: a
/// display with no stored entry resolves through ``globalConfiguration``.
///
/// `makeManager` trips the manager's persisting `didSet` observers, so each
/// case runs inside `withScratchDefaults`: the writes land in a throwaway
/// store instead of the developer's own display settings.
@MainActor
@Suite("Display settings global fallback", .serialized)
final class DisplaySettingsManagerGlobalFallbackTests {
    private let global = DisplayIceBarConfiguration
        .defaultConfiguration
        .withItemSpacingOffset(-16)

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
    func unresolvableDisplayFallsBackToGlobalConfiguration() throws {
        try withScratchDefaults { _ in
            let resolved = makeManager().configuration(for: 0)

            #expect(resolved == global)
            #expect(resolved.itemSpacingOffset == -16)
        }
    }

    @Test("A resolved display uses its explicit configuration")
    func resolvedDisplayUsesExplicitConfiguration() throws {
        try withScratchDefaults { _ in
            let displayID = CGMainDisplayID()
            let uuid = try #require(Bridging.getDisplayUUIDString(for: displayID))
            let explicit = DisplayIceBarConfiguration
                .defaultConfiguration
                .withItemSpacingOffset(11)
            let manager = makeManager(configurations: [uuid: explicit])

            #expect(manager.configuration(for: displayID) == explicit)
        }
    }

    @Test("A resolved display without an override inherits the global configuration")
    func resolvedDisplayWithoutOverrideFallsBackToGlobalConfiguration() throws {
        try withScratchDefaults { _ in
            let displayID = CGMainDisplayID()
            guard Bridging.getDisplayUUIDString(for: displayID) != nil else {
                return // No resolvable display in this environment.
            }

            #expect(makeManager().configuration(for: displayID) == global)
        }
    }

    @Test("The active display without an override inherits the global configuration")
    func activeDisplayWithoutOverrideFallsBackToGlobalConfiguration() throws {
        try withScratchDefaults { _ in
            #expect(makeManager().configurationForActiveDisplay() == global)
        }
    }

    @Test("The active display uses its explicit configuration")
    func activeDisplayUsesExplicitConfiguration() throws {
        try withScratchDefaults { _ in
            guard let uuid = Bridging.getActiveMenuBarDisplayUUID() else {
                return // No resolvable display in this environment.
            }
            let explicit = DisplayIceBarConfiguration
                .defaultConfiguration
                .withItemSpacingOffset(9)
            let manager = makeManager(configurations: [uuid: explicit])

            #expect(manager.configurationForActiveDisplay() == explicit)
        }
    }

    /// The offset behind these cases is what gets pushed into
    /// `MenuBarItemSpacingManager.offset` at launch, on a display transition,
    /// and on a profile apply. A profile apply used to skip the push when the
    /// incoming configurations matched the live ones, leaving the offset at
    /// its launch value of 0 and relaunching every menu bar app to write the
    /// system default over the user's spacing.
    @Test("The active display's offset comes from the global fallback")
    func activeDisplaySpacingOffsetFallsBackToGlobalConfiguration() throws {
        try withScratchDefaults { _ in
            #expect(makeManager().activeDisplaySpacingOffset == -16)
        }
    }

    @Test("The active display's offset comes from its explicit configuration")
    func activeDisplaySpacingOffsetUsesExplicitConfiguration() throws {
        try withScratchDefaults { _ in
            guard let uuid = Bridging.getActiveMenuBarDisplayUUID() else {
                return // No resolvable display in this environment.
            }
            let explicit = DisplayIceBarConfiguration
                .defaultConfiguration
                .withItemSpacingOffset(9)
            let manager = makeManager(configurations: [uuid: explicit])

            #expect(manager.activeDisplaySpacingOffset == 9)
        }
    }

    @Test(
        "A fractional offset rounds to the nearest whole point",
        arguments: [(2.4, 2), (2.5, 3), (-2.4, -2), (-2.6, -3)]
    )
    func activeDisplaySpacingOffsetRounds(stored: Double, expected: Int) throws {
        try withScratchDefaults { _ in
            let manager = makeManager(
                globalConfiguration: .defaultConfiguration.withItemSpacingOffset(stored)
            )

            #expect(manager.activeDisplaySpacingOffset == expected)
        }
    }

    @Test("A UUID lookup uses its explicit configuration")
    func uuidLookupUsesExplicitConfiguration() throws {
        try withScratchDefaults { _ in
            let explicit = DisplayIceBarConfiguration
                .defaultConfiguration
                .withItemSpacingOffset(8)
            let manager = makeManager(configurations: ["UUID-A": explicit])

            #expect(manager.configuration(forUUID: "UUID-A") == explicit)
        }
    }

    @Test("A missing UUID inherits the global configuration")
    func uuidLookupWithoutOverrideFallsBackToGlobalConfiguration() throws {
        try withScratchDefaults { _ in
            #expect(makeManager().configuration(forUUID: "UUID-MISSING") == global)
        }
    }

    @Test("The override lookup distinguishes stored entries from the template")
    func configurationOverrideDistinguishesStoredEntriesFromTemplate() throws {
        try withScratchDefaults { _ in
            let explicit = DisplayIceBarConfiguration
                .defaultConfiguration
                .withUseIceBar(true)
            let manager = makeManager(configurations: ["UUID-A": explicit])

            // A stored entry comes back as-is, so the pane can mark the
            // display as custom (#1045)...
            #expect(manager.configurationOverride(forUUID: "UUID-A") == explicit)
            // ...and a display with no entry reads as having none, even
            // though the resolved configuration would equal the template.
            #expect(manager.configurationOverride(forUUID: "UUID-MISSING") == nil)
            #expect(manager.configuration(forUUID: "UUID-MISSING") == global)
        }
    }

    @Test("The default global configuration preserves the previous fallback")
    func defaultGlobalConfigurationPreservesPreviousFallback() throws {
        try withScratchDefaults { _ in
            let manager = makeManager(globalConfiguration: .defaultConfiguration)

            #expect(
                manager.configuration(forUUID: "UUID-MISSING") == .defaultConfiguration
            )
        }
    }
}
