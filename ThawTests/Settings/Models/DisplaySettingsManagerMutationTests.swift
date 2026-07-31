//
//  DisplaySettingsManagerMutationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers ``DisplaySettingsManager``'s mutation and enumeration surface:
/// `updateConfiguration`, the typed lookups built on it,
/// `applyGlobalToAllKnownDisplays`, and the `allDisplays` ordering.
///
/// The inheritance rule these share is the point: a display with no stored
/// entry reads — and is *edited* — through ``globalConfiguration``, so
/// changing one field on an unconfigured display must not silently reset the
/// others to the hardcoded defaults.
///
/// `performSetup`, the spacing apply, and the external-notification observer
/// all need a live `AppState` and are out of reach here.
/// `DisplaySettingsManagerGlobalFallbackTests` covers the read side;
/// `DisplaySettingsManagerSpacingGateTests` covers the apply gate.
///
/// The manager persists through `didSet`, and `Defaults` is hardcoded to
/// `.standard`, so the suite snapshots the keys it touches.
@MainActor
@Suite("Display settings mutation", .serialized)
final class DisplaySettingsManagerMutationTests {
    private static let touchedKeys: [Defaults.Key] = [
        .displayIceBarConfigurations,
        .globalDisplayConfiguration,
        .knownDisplays,
    ]

    private let savedDefaults: [Defaults.Key: Data?]

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

    /// A manager with a distinctive global template and no per-display
    /// entries, so inheritance is observable.
    private func makeManager(
        configurations: [String: DisplayIceBarConfiguration] = [:]
    ) -> DisplaySettingsManager {
        let manager = DisplaySettingsManager()
        manager.globalConfiguration = .defaultConfiguration
            .withItemSpacingOffset(-7)
            .withGridColumns(6)
        manager.configurations = configurations
        return manager
    }

    // MARK: updateConfiguration

    @Test("An edit to an unconfigured display keeps the rest of the global template")
    func editingAnUnconfiguredDisplayInheritsTheGlobal() {
        let manager = makeManager()

        manager.updateConfiguration(forDisplayUUID: "UUID-A") { $0.withUseIceBar(true) }

        let result = manager.configuration(forUUID: "UUID-A")
        #expect(result.useIceBar, "the edited field must take")
        #expect(result.itemSpacingOffset == -7, "the inherited offset must survive the edit")
        #expect(result.gridColumns == 6, "the inherited column count must survive the edit")
    }

    @Test("An edit to a configured display keeps that display's own values")
    func editingAConfiguredDisplayKeepsItsValues() {
        let explicit = DisplayIceBarConfiguration.defaultConfiguration
            .withItemSpacingOffset(3)
            .withGridColumns(9)
        let manager = makeManager(configurations: ["UUID-A": explicit])

        manager.updateConfiguration(forDisplayUUID: "UUID-A") { $0.withUseIceBar(true) }

        let result = manager.configuration(forUUID: "UUID-A")
        #expect(result.useIceBar)
        #expect(result.itemSpacingOffset == 3)
        #expect(result.gridColumns == 9)
    }

    @Test("An edit creates the entry rather than leaving the display unconfigured")
    func editingCreatesAnEntry() {
        let manager = makeManager()
        #expect(manager.configurations["UUID-A"] == nil)

        manager.updateConfiguration(forDisplayUUID: "UUID-A") { $0.withUseIceBar(true) }

        #expect(manager.configurations["UUID-A"] != nil)
    }

    @Test("An edit leaves every other display alone")
    func editingIsScopedToItsDisplay() {
        let other = DisplayIceBarConfiguration.defaultConfiguration.withItemSpacingOffset(11)
        let manager = makeManager(configurations: ["UUID-B": other])

        manager.updateConfiguration(forDisplayUUID: "UUID-A") { $0.withUseIceBar(true) }

        #expect(manager.configurations["UUID-B"] == other)
    }

    @Test("An edit persists to Defaults")
    func editingPersists() throws {
        let manager = makeManager()

        manager.updateConfiguration(forDisplayUUID: "UUID-A") { $0.withUseIceBar(true) }

        let data = try #require(Defaults.data(forKey: .displayIceBarConfigurations))
        let decoded = try JSONDecoder().decode([String: DisplayIceBarConfiguration].self, from: data)
        #expect(decoded["UUID-A"]?.useIceBar == true)
    }

    @Test("A transform that changes nothing still leaves a valid entry")
    func identityTransformIsHarmless() {
        let manager = makeManager()

        manager.updateConfiguration(forDisplayUUID: "UUID-A") { $0 }

        #expect(manager.configuration(forUUID: "UUID-A") == manager.globalConfiguration)
    }

    // MARK: Typed lookups

    @Test("The typed lookups agree with the stored configuration")
    func typedLookupsMatchTheConfiguration() {
        let manager = makeManager()
        let displayID = CGMainDisplayID()
        guard let uuid = Bridging.getDisplayUUIDString(for: displayID) else {
            return // No resolvable display in this environment.
        }

        manager.updateConfiguration(forDisplayUUID: uuid) {
            $0.withUseIceBar(true).withIceBarLayout(.grid).withGridColumns(5)
        }

        #expect(manager.useIceBar(for: displayID))
        #expect(manager.iceBarLayout(for: displayID) == .grid)
        #expect(manager.gridColumns(for: displayID) == 5)
        #expect(manager.alwaysShowHiddenItems(for: displayID) == false)
        #expect(manager.iceBarLocation(for: displayID) == .dynamic)
    }

    @Test("An unresolvable display falls back to the global template")
    func unresolvableDisplayUsesTheGlobal() {
        let manager = makeManager()

        // Display ID 0 resolves to no UUID.
        #expect(manager.gridColumns(for: 0) == 6)
        #expect(manager.configuration(for: 0).itemSpacingOffset == -7)
    }

    // MARK: Global broadcast

    @Test("Broadcasting the global writes it to every known display")
    func globalBroadcastWritesEveryDisplay() {
        let manager = makeManager(configurations: ["UUID-A": .defaultConfiguration])
        manager.knownDisplays = [
            "UUID-A": KnownDisplay(name: "Alpha", hasNotch: false),
            "UUID-B": KnownDisplay(name: "Beta", hasNotch: false),
        ]

        let targets = manager.applyGlobalToAllKnownDisplays()

        #expect(Set(targets).isSuperset(of: ["UUID-A", "UUID-B"]))
        for uuid in targets {
            #expect(manager.configurations[uuid] == manager.globalConfiguration, "\(uuid)")
        }
    }

    @Test("Broadcasting with no known displays reports no targets")
    func globalBroadcastWithNoDisplays() {
        let manager = makeManager()
        manager.knownDisplays = [:]

        // Connected displays still count, so only assert the contract that
        // every reported target ended up holding the template.
        for uuid in manager.applyGlobalToAllKnownDisplays() {
            #expect(manager.configurations[uuid] == manager.globalConfiguration, "\(uuid)")
        }
    }

    // MARK: Display enumeration

    @Test("Disconnected known displays are listed after connected ones")
    func allDisplaysOrdersConnectedFirst() {
        let manager = makeManager()
        manager.knownDisplays = [
            "UUID-Zed": KnownDisplay(name: "Zed", hasNotch: false),
            "UUID-Abe": KnownDisplay(name: "Abe", hasNotch: false),
        ]

        let all = manager.allDisplays()
        let connectedCount = all.prefix { $0.isConnected }.count

        #expect(all.dropFirst(connectedCount).allSatisfy { !$0.isConnected })
        let disconnectedNames = all.filter { !$0.isConnected }.map(\.name)
        #expect(disconnectedNames == disconnectedNames.sorted(), "disconnected rows sort by name")
    }

    @Test("A cached display with a blank name is not surfaced")
    func blankNamedDisplaysAreHidden() {
        let manager = makeManager()
        manager.knownDisplays = [
            "UUID-Blank": KnownDisplay(name: "   ", hasNotch: false),
            "UUID-Named": KnownDisplay(name: "Named", hasNotch: false),
        ]

        let ids = manager.allDisplays().map(\.id)

        #expect(!ids.contains("UUID-Blank"))
        #expect(ids.contains("UUID-Named"))
    }

    @Test("A stored configuration with no cached name is not surfaced")
    func configuredButUnnamedDisplaysAreHidden() {
        let manager = makeManager(configurations: ["UUID-Orphan": .defaultConfiguration])
        manager.knownDisplays = [:]

        #expect(!manager.allDisplays().map(\.id).contains("UUID-Orphan"))
    }

    @Test("Every connected display reports a name and an identifier")
    func connectedDisplaysAreWellFormed() {
        let manager = makeManager()

        for display in manager.connectedDisplays() {
            #expect(display.isConnected)
            #expect(display.displayID != nil)
            #expect(!display.name.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!display.id.isEmpty)
        }
    }

    // MARK: Persistence round-trip

    @Test("Configurations survive a reload")
    func configurationsRoundTripThroughDefaults() {
        let manager = makeManager()
        manager.updateConfiguration(forDisplayUUID: "UUID-A") {
            $0.withUseIceBar(true).withGridColumns(8)
        }

        let reloaded = DisplaySettingsManager()

        #expect(reloaded.configurations["UUID-A"]?.useIceBar == true)
        #expect(reloaded.configurations["UUID-A"]?.gridColumns == 8)
    }

    @Test("The global template survives a reload")
    func globalConfigurationRoundTripsThroughDefaults() {
        let manager = makeManager()
        manager.globalConfiguration = .defaultConfiguration.withItemSpacingOffset(-13)

        let reloaded = DisplaySettingsManager()

        #expect(reloaded.globalConfiguration.itemSpacingOffset == -13)
    }
}
