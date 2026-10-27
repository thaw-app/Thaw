//
//  DisplaySettingsManagerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The per-display settings model on its own, with settings in a throwaway suite.
/// No manager here is wired to an AppState, so no spacing is ever applied.
@MainActor
@Suite("Display settings manager", .serialized, .scratchDefaults)
struct DisplaySettingsManagerTests {
    private static let uuid = "TEST-DISPLAY-UUID"

    /// A manager that starts from an empty saved dictionary, so the system's
    /// own spacing value never seeds anything.
    private func makeManager(
        configurations: [String: DisplayThawBarConfiguration] = [:]
    ) throws -> DisplaySettingsManager {
        try Defaults.set(JSONEncoder().encode(configurations), forKey: .displayThawBarConfigurations)
        return DisplaySettingsManager()
    }

    private func stored<T: Decodable>(_ type: T.Type, _ key: Defaults.Key) throws -> T {
        try JSONDecoder().decode(type, from: #require(Defaults.data(forKey: key)))
    }

    @Test("Saved configurations, template, known displays and spacing settings load at start")
    func loadsSavedState() throws {
        let config = DisplayThawBarConfiguration.defaultConfiguration.withUseThawBar(true).withGridColumns(6)
        let global = DisplayThawBarConfiguration.defaultConfiguration.withThawBarLocation(.mousePointer)
        try Defaults.set(JSONEncoder().encode(global), forKey: .globalDisplayConfiguration)
        try Defaults.set(
            JSONEncoder().encode(["A": KnownDisplay(name: "Studio", hasNotch: false), "B": KnownDisplay(name: "  ", hasNotch: true)]),
            forKey: .knownDisplays
        )
        Defaults.set(false, forKey: .confirmSpacingRelaunch)
        Defaults.set(SpacingProfileSaveScope.allProfiles.rawValue, forKey: .unconfirmedSpacingProfileScope)

        let manager = try makeManager(configurations: [Self.uuid: config])

        #expect(manager.configurations == [Self.uuid: config])
        #expect(manager.globalConfiguration == global)
        #expect(manager.knownDisplays == ["A": KnownDisplay(name: "Studio", hasNotch: false)], "blank names are dropped")
        #expect(manager.confirmSpacingRelaunch == false)
        #expect(manager.unconfirmedSpacingProfileScope == .allProfiles)
        #expect(manager.lastPersistenceFailure == nil)
    }

    @Test("Stored values that cannot be decoded are ignored")
    func ignoresGarbage() {
        Defaults.set(Data("x".utf8), forKey: .displayThawBarConfigurations)
        Defaults.set(Data("x".utf8), forKey: .globalDisplayConfiguration)
        Defaults.set(Data("x".utf8), forKey: .knownDisplays)
        Defaults.set("nonsense", forKey: .unconfirmedSpacingProfileScope)
        Defaults.set("nonsense", forKey: .spacingApplyMode)

        let manager = DisplaySettingsManager()

        #expect(manager.configurations.isEmpty)
        #expect(manager.globalConfiguration == .defaultConfiguration)
        #expect(manager.knownDisplays.isEmpty)
        #expect(manager.unconfirmedSpacingProfileScope == Defaults.DefaultValue.unconfirmedSpacingProfileScope)
        #expect(manager.spacingApplyMode == Defaults.DefaultValue.spacingApplyMode)
    }

    @Test("Each setting writes through to Defaults when it changes")
    func persistsChanges() throws {
        let manager = try makeManager()
        let config = DisplayThawBarConfiguration.defaultConfiguration.withAlwaysShowHiddenItems(true)

        manager.configurations = [Self.uuid: config]
        manager.globalConfiguration = config
        manager.knownDisplays = [Self.uuid: KnownDisplay(name: "Desk", hasNotch: true)]
        manager.confirmSpacingRelaunch = !Defaults.DefaultValue.confirmSpacingRelaunch
        manager.unconfirmedSpacingProfileScope = .allProfiles
        let otherMode = SpacingApplyMode.allCases.first { $0 != manager.spacingApplyMode }
        if let otherMode {
            manager.spacingApplyMode = otherMode
            #expect(Defaults.string(forKey: .spacingApplyMode) == otherMode.rawValue)
        }

        #expect(try stored([String: DisplayThawBarConfiguration].self, .displayThawBarConfigurations) == [Self.uuid: config])
        #expect(try stored(DisplayThawBarConfiguration.self, .globalDisplayConfiguration) == config)
        #expect(try stored([String: KnownDisplay].self, .knownDisplays)[Self.uuid]?.name == "Desk")
        #expect(Defaults.bool(forKey: .confirmSpacingRelaunch) == !Defaults.DefaultValue.confirmSpacingRelaunch)
        #expect(Defaults.string(forKey: .unconfirmedSpacingProfileScope) == "allProfiles")

        let reloaded = DisplaySettingsManager()
        #expect(reloaded.configurations == [Self.uuid: config])
        #expect(reloaded.globalConfiguration == config)
        #expect(reloaded.unconfirmedSpacingProfileScope == .allProfiles)
    }

    @Test("A display with no entry of its own resolves to the template")
    func resolution() throws {
        let own = DisplayThawBarConfiguration.defaultConfiguration.withUseThawBar(true)
        let manager = try makeManager(configurations: [Self.uuid: own])
        manager.globalConfiguration = DisplayThawBarConfiguration.defaultConfiguration.withGridColumns(9)

        #expect(manager.configuration(forUUID: Self.uuid) == own)
        #expect(manager.configuration(forUUID: "other") == manager.globalConfiguration)
        #expect(DisplaySettingsManager.resolvedConfiguration(displayUUID: nil, configurations: [Self.uuid: own], globalConfiguration: .defaultConfiguration) == .defaultConfiguration)
        #expect(manager.configuration(for: 0xFFFF_FFF0) == manager.globalConfiguration, "an unknown display ID has no UUID")
        #expect(!manager.useThawBar(for: 0xFFFF_FFF0))
        #expect(manager.thawBarLocation(for: 0xFFFF_FFF0) == manager.globalConfiguration.thawBarLocation)
        #expect(!manager.alwaysShowHiddenItems(for: 0xFFFF_FFF0))
    }

    @Test("Updating a display starts from its resolved configuration")
    func updateConfiguration() throws {
        let manager = try makeManager()
        manager.globalConfiguration = DisplayThawBarConfiguration.defaultConfiguration.withGridColumns(5)
        manager.updateConfiguration(forDisplayUUID: Self.uuid) { $0.withUseThawBar(true) }
        #expect(manager.configurations[Self.uuid]?.useThawBar == true)
        #expect(manager.configurations[Self.uuid]?.gridColumns == 5)
    }

    @Test("Apply to all copies the template onto every known display, connected or not")
    func applyGlobalToAll() throws {
        let manager = try makeManager()
        manager.knownDisplays = ["OFFLINE": KnownDisplay(name: "Offline", hasNotch: false)]
        manager.globalConfiguration = DisplayThawBarConfiguration.defaultConfiguration.withThawBarLayout(.grid)

        let targets = manager.applyGlobalToAllKnownDisplays()

        #expect(targets.contains("OFFLINE"))
        for uuid in targets {
            #expect(manager.configurations[uuid] == manager.globalConfiguration)
        }
    }

    @Test("Known displays that are not connected are listed after connected ones")
    func displaysList() throws {
        let manager = try makeManager()
        manager.knownDisplays = [
            "Z": KnownDisplay(name: "Zeta", hasNotch: false),
            "Y": KnownDisplay(name: "Alpha", hasNotch: true),
        ]
        let offline = manager.displays.filter { !$0.isConnected }
        #expect(offline.map(\.name) == ["Alpha", "Zeta"])
        #expect(offline.allSatisfy { $0.displayID == nil })
        #expect(offline.first?.hasNotch == true)
        let connected = manager.displays.filter(\.isConnected)
        #expect(connected.count == manager.connectedDisplays().count)
        let leading = manager.displays.prefix(connected.count).allSatisfy(\.isConnected)
        #expect(leading)
    }

    @Test("The wide display rule turns always-show on somewhere")
    func alwaysShowAnywhere() throws {
        let manager = try makeManager()
        manager.wideDisplayRule.isEnabled = true
        #expect(manager.isAlwaysShowEnabledOnAnyDisplay)
    }

    @Test("Assigning configurations as write-only clears the reason afterwards")
    func assignWriteOnly() throws {
        let manager = try makeManager()
        let config = DisplayThawBarConfiguration.defaultConfiguration.withItemSpacingOffset(3)
        manager.assignConfigurations([Self.uuid: config], writeOnly: true)
        #expect(manager.configurations[Self.uuid] == config)
        #expect(manager.writeOnlyConfigurationsReason == nil)
        manager.assignConfigurations([:], writeOnly: false)
        #expect(manager.configurations.isEmpty)
    }

    @Test("A display change with no app state applies nothing")
    func displayChangeWithoutAppState() throws {
        let manager = try makeManager()
        manager.lastAppliedActiveDisplayUUID = "stale"
        manager.applySpacingForDisplayChange()
        #expect(manager.lastAppliedActiveDisplayUUID == "stale", "without an app state nothing is applied")
        manager.reapplySpacing(forDisplayUUID: "not the active display")
        #expect(!manager.isReapplyingSpacing)
    }

    // MARK: Spacing decisions

    @Test("Only a display change, seeding or a display profile switch saves spacing without relaunching")
    func relaunchReasons() {
        #expect(!DisplaySettingsManager.spacingApplyRelaunchesApps(reason: "screenParametersChanged"))
        #expect(!DisplaySettingsManager.spacingApplyRelaunchesApps(reason: "displaySeeded"))
        #expect(!DisplaySettingsManager.spacingApplyRelaunchesApps(reason: DisplaySettingsManager.displayProfileSwitchReason))
        #expect(DisplaySettingsManager.spacingApplyRelaunchesApps(reason: "configurationsChanged"))
        #expect(DisplaySettingsManager.configurationsChangeReason(writeOnlyReason: nil) == "configurationsChanged")
        #expect(DisplaySettingsManager.configurationsChangeReason(writeOnlyReason: "x") == "x")
        #expect(DisplaySettingsManager.displayChangeSpacingReason(currentActiveDisplayUUID: "a", lastAppliedActiveDisplayUUID: "a") == nil)
        #expect(DisplaySettingsManager.displayChangeSpacingReason(currentActiveDisplayUUID: "a", lastAppliedActiveDisplayUUID: "b") == "screenParametersChanged")
        #expect(DisplaySettingsManager.needsSpacingRelaunchConfirmation(applyMode: .relaunchApps, confirmationsEnabled: true))
        #expect(!DisplaySettingsManager.needsSpacingRelaunchConfirmation(applyMode: .relaunchApps, confirmationsEnabled: false))
    }
}

/// The immutable per-display configuration value.
@Suite("Display Thaw Bar configuration")
struct DisplayThawBarConfigurationTests {
    @Test("Each with-method changes one field and keeps the rest")
    func withMethods() {
        let base = DisplayThawBarConfiguration.defaultConfiguration
        let changed = base
            .withUseThawBar(true)
            .withThawBarLocation(.leftAligned)
            .withAlwaysShowHiddenItems(true)
            .withThawBarLayout(.vertical)
            .withGridColumns(6)
            .withItemSpacingOffset(-3)
        #expect(changed.useThawBar)
        #expect(changed.thawBarLocation == .leftAligned)
        #expect(changed.alwaysShowHiddenItems)
        #expect(changed.thawBarLayout == .vertical)
        #expect(changed.gridColumns == 6)
        #expect(changed.itemSpacingOffset == -3)
        #expect(base.withUseThawBar(false) == base)
    }

    @Test("Columns and spacing are clamped to their ranges")
    func clamping() {
        let base = DisplayThawBarConfiguration.defaultConfiguration
        #expect(base.withGridColumns(0).gridColumns == 2)
        #expect(base.withGridColumns(50).gridColumns == 10)
        #expect(base.withItemSpacingOffset(40).itemSpacingOffset == 16)
        #expect(base.withItemSpacingOffset(-40).itemSpacingOffset == -16)
    }

    @Test("Older entries without layout, columns or spacing decode with defaults and clamps")
    func decodesOlderEntries() throws {
        let old = try JSONDecoder().decode(
            DisplayThawBarConfiguration.self,
            from: Data(#"{"useIceBar": true, "iceBarLocation": 2, "alwaysShowHiddenItems": false}"#.utf8)
        )
        #expect(old.useThawBar)
        #expect(old.thawBarLocation == .thawIcon)
        #expect(old.thawBarLayout == .horizontal)
        #expect(old.gridColumns == 4)
        #expect(old.itemSpacingOffset == 0)

        let wild = try JSONDecoder().decode(
            DisplayThawBarConfiguration.self,
            from: Data(#"{"useIceBar": false, "iceBarLocation": 0, "alwaysShowHiddenItems": true, "gridColumns": 99, "itemSpacingOffset": -99}"#.utf8)
        )
        #expect(wild.gridColumns == 10)
        #expect(wild.itemSpacingOffset == -16)
    }

    @Test("Encoding keeps the Ice-era keys")
    func encodedKeys() throws {
        let data = try JSONEncoder().encode(DisplayThawBarConfiguration.defaultConfiguration)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["useIceBar", "iceBarLocation", "alwaysShowHiddenItems", "iceBarLayout", "gridColumns", "itemSpacingOffset"])
    }

    @Test("Configurations built for connected screens cover each one with the chosen location")
    @MainActor
    func buildConfigurations() {
        let all = DisplayThawBarConfiguration.buildConfigurations(onlyOnNotched: false, location: .mousePointer)
        #expect(all.values.allSatisfy { $0.useThawBar && $0.thawBarLocation == .mousePointer })
        let notched = DisplayThawBarConfiguration.buildConfigurations(onlyOnNotched: true, location: .dynamic)
        #expect(notched.count == all.count)
        #expect(notched.values.allSatisfy { $0.thawBarLocation == .dynamic })
    }
}
