//
//  DisplaySettingsExternalChangeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Per-display changes that arrive through thaw:// URLs, handed straight to the manager
/// so no other manager in the process sees them. Settings live in a throwaway suite.
@MainActor
@Suite("Display settings changed from outside", .serialized, .scratchDefaults)
struct DisplaySettingsExternalChangeTests {
    private static let uuid = "EXTERNAL-CHANGE-UUID"

    private func makeManager(
        configurations: [String: DisplayThawBarConfiguration] = [:]
    ) throws -> DisplaySettingsManager {
        try Defaults.set(JSONEncoder().encode(configurations), forKey: .displayThawBarConfigurations)
        return DisplaySettingsManager()
    }

    private func send(
        _ manager: DisplaySettingsManager,
        key: String,
        scope: String = "specific:\(Self.uuid)",
        _ extra: [String: Any] = [:]
    ) {
        var info: [String: Any] = ["key": key, "scope": scope]
        info.merge(extra) { _, new in new }
        manager.handleExternalPerDisplaySettingsChange(
            Notification(name: .perDisplaySettingsDidChangeViaURI, object: nil, userInfo: info)
        )
    }

    private var connectedUUIDs: [String] {
        NSScreen.managedScreens.compactMap { Bridging.getDisplayUUIDString(for: $0.displayID) }
    }

    private var base: DisplayThawBarConfiguration {
        .defaultConfiguration
    }

    @Test("A change without a key or scope, or for a display Thaw has never seen, is ignored")
    func ignoresIncompleteAndUnknown() throws {
        let manager = try makeManager(configurations: [Self.uuid: base])

        manager.handleExternalPerDisplaySettingsChange(
            Notification(name: .perDisplaySettingsDidChangeViaURI, object: nil, userInfo: ["key": "useThawBar"])
        )
        send(manager, key: "useThawBar", scope: "specific:NO-SUCH-DISPLAY", ["value": true])
        send(manager, key: "noSuchKey", ["value": true])

        #expect(manager.configurations == [Self.uuid: base])
        #expect(manager.configurations["NO-SUCH-DISPLAY"] == nil)
    }

    @Test("useThawBar sets and toggles one display")
    func useThawBarOnOneDisplay() throws {
        let manager = try makeManager(configurations: [Self.uuid: base.withUseThawBar(false)])

        send(manager, key: "useThawBar", ["value": true])
        #expect(manager.configuration(forUUID: Self.uuid).useThawBar)

        send(manager, key: "useThawBar", ["toggle": true])
        #expect(!manager.configuration(forUUID: Self.uuid).useThawBar)

        send(manager, key: "useThawBar", ["value": "yes"])
        #expect(!manager.configuration(forUUID: Self.uuid).useThawBar, "a value that isn't a Bool changes nothing")
    }

    @Test("useThawBar without a display acts on the one that has the menu bar")
    func useThawBarOnActiveDisplay() throws {
        let manager = try makeManager()
        let active = Bridging.getActiveMenuBarDisplayUUID()

        send(manager, key: "useThawBar", scope: "active", ["value": true])
        send(manager, key: "useThawBar", scope: "active", ["toggle": true])
        send(manager, key: "useThawBar", scope: "active", ["toggle": true])

        if let active {
            #expect(manager.configuration(forUUID: active).useThawBar)
        } else {
            #expect(manager.configurations.isEmpty)
        }
    }

    @Test("Location, layout and columns parse their string values for one display")
    func stringValuesOnOneDisplay() throws {
        let manager = try makeManager(configurations: [Self.uuid: base])

        send(manager, key: "thawBarLocation", ["stringValue": String(ThawBarLocation.mousePointer.rawValue)])
        send(manager, key: "thawBarLayout", ["stringValue": "grid"])
        send(manager, key: "gridColumns", ["stringValue": "7"])

        var config = manager.configuration(forUUID: Self.uuid)
        #expect(config.thawBarLocation == .mousePointer)
        #expect(config.thawBarLayout == .grid)
        #expect(config.gridColumns == 7)

        send(manager, key: "thawBarLocation", ["stringValue": "99"])
        send(manager, key: "thawBarLocation", ["stringValue": "left"])
        send(manager, key: "thawBarLayout", ["stringValue": "diagonal"])
        send(manager, key: "gridColumns", ["stringValue": "many"])
        #expect(manager.configuration(forUUID: Self.uuid) == config, "values that don't parse change nothing")

        send(manager, key: "gridColumns", ["stringValue": "50"])
        config = manager.configuration(forUUID: Self.uuid)
        #expect(config.gridColumns == 10)
        send(manager, key: "gridColumns", ["stringValue": "1"])
        #expect(manager.configuration(forUUID: Self.uuid).gridColumns == 2)
    }

    @Test("alwaysShowHiddenItems sets and toggles one display")
    func alwaysShowOnOneDisplay() throws {
        let manager = try makeManager(configurations: [Self.uuid: base.withAlwaysShowHiddenItems(false)])

        send(manager, key: "alwaysShowHiddenItems", ["value": true])
        #expect(manager.configuration(forUUID: Self.uuid).alwaysShowHiddenItems)

        send(manager, key: "alwaysShowHiddenItems", ["toggle": true])
        #expect(!manager.configuration(forUUID: Self.uuid).alwaysShowHiddenItems)
    }

    @Test("Location, layout and columns for all enabled displays only touch displays using the Thaw Bar")
    func allEnabledDisplays() throws {
        let uuids = connectedUUIDs
        var configurations: [String: DisplayThawBarConfiguration] = [Self.uuid: base.withUseThawBar(true)]
        for (index, uuid) in uuids.enumerated() {
            configurations[uuid] = base.withUseThawBar(index.isMultiple(of: 2))
        }
        let manager = try makeManager(configurations: configurations)

        send(manager, key: "thawBarLocation", scope: "allEnabled", ["stringValue": String(ThawBarLocation.leftAligned.rawValue)])
        send(manager, key: "thawBarLayout", scope: "allEnabled", ["stringValue": "vertical"])
        send(manager, key: "gridColumns", scope: "allEnabled", ["stringValue": "3"])

        for (index, uuid) in uuids.enumerated() {
            let config = manager.configuration(forUUID: uuid)
            let enabled = index.isMultiple(of: 2)
            #expect((config.thawBarLocation == .leftAligned) == enabled)
            #expect((config.thawBarLayout == .vertical) == enabled)
            #expect((config.gridColumns == 3) == enabled)
        }
        #expect(manager.configuration(forUUID: Self.uuid) == base.withUseThawBar(true), "a display that isn't connected is skipped")
    }

    @Test("Always show for displays without the Thaw Bar skips displays that use it, under either spelling")
    func allNonThawBarDisplays() throws {
        let uuids = connectedUUIDs
        var configurations: [String: DisplayThawBarConfiguration] = [:]
        for (index, uuid) in uuids.enumerated() {
            configurations[uuid] = base.withUseThawBar(!index.isMultiple(of: 2)).withAlwaysShowHiddenItems(false)
        }
        let manager = try makeManager(configurations: configurations)

        send(manager, key: "alwaysShowHiddenItems", scope: "allNonThawBar", ["value": true])
        for (index, uuid) in uuids.enumerated() {
            #expect(manager.configuration(forUUID: uuid).alwaysShowHiddenItems == index.isMultiple(of: 2))
        }

        send(manager, key: "alwaysShowHiddenItems", scope: "allNonIceBar", ["toggle": true])
        for uuid in uuids {
            #expect(!manager.configuration(forUUID: uuid).alwaysShowHiddenItems)
        }
    }

    @Test("Scopes a setting doesn't support leave every display alone")
    func unsupportedScopes() throws {
        let uuids = connectedUUIDs
        var configurations: [String: DisplayThawBarConfiguration] = [:]
        for uuid in uuids {
            configurations[uuid] = base.withUseThawBar(true)
        }
        let manager = try makeManager(configurations: configurations)
        let before = manager.configurations

        send(manager, key: "thawBarLocation", scope: "active", ["stringValue": String(ThawBarLocation.mousePointer.rawValue)])
        send(manager, key: "thawBarLayout", scope: "allNonThawBar", ["stringValue": "grid"])
        send(manager, key: "gridColumns", scope: "somewhere", ["stringValue": "5"])
        send(manager, key: "alwaysShowHiddenItems", scope: "allEnabled", ["value": true])
        send(manager, key: "alwaysShowHiddenItems", scope: "active", ["toggle": true])

        #expect(manager.configurations == before)
    }

    @Test("Toggling the Thaw Bar for the active display flips that display only")
    func toggleActiveDisplay() throws {
        let manager = try makeManager()
        manager.toggleThawBarForActiveDisplay()

        if let active = Bridging.getActiveMenuBarDisplayUUID() {
            #expect(manager.configuration(forUUID: active).useThawBar != manager.globalConfiguration.useThawBar)
            #expect(manager.configurations.count == 1)
        } else {
            #expect(manager.configurations.isEmpty)
        }
    }

    @Test("Spacing set outside Thaw seeds connected displays that have no entry yet")
    func seedsFromSystemSpacing() throws {
        let uuids = connectedUUIDs
        let manager = try makeManager(configurations: [Self.uuid: base])

        manager.seedConfigurationsFromSystemSpacing(nil)
        manager.seedConfigurationsFromSystemSpacing(16)
        #expect(manager.configurations == [Self.uuid: base], "no value, or the system default, seeds nothing")

        manager.seedConfigurationsFromSystemSpacing(12)
        for uuid in uuids {
            #expect(manager.configurations[uuid]?.itemSpacingOffset == -4)
        }
        #expect(manager.configurations[Self.uuid] == base, "displays with an entry keep it")
        if !uuids.isEmpty {
            let stored = try JSONDecoder().decode(
                [String: DisplayThawBarConfiguration].self,
                from: #require(Defaults.data(forKey: .displayThawBarConfigurations))
            )
            #expect(stored == manager.configurations)
        }

        let before = manager.configurations
        manager.seedConfigurationsFromSystemSpacing(20)
        #expect(manager.configurations == before, "a second pass finds every display already seeded")
    }
}
