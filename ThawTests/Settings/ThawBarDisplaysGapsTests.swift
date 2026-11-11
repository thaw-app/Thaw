//
//  ThawBarDisplaysGapsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Thaw Bar and Displays", .serialized, .scratchDefaults)
struct ThawBarDisplaysGapsTests {
    private typealias World = LayoutEditorWorld

    // MARK: Shared items

    @Test("The bar and its preview leave out apps you switched off, and a folder shows its members")
    func sharedItems() {
        let world = World()
        let alpha = World.item("Alpha")
        let beta = World.item("Beta")
        world.seat([alpha, beta], in: .hidden)
        let manager = world.appState.itemManager

        #expect(ThawBarItems.items(in: .hidden, itemManager: manager, switchedOff: []).count == 2)
        let bundleID = "com.example.Alpha"
        let filtered = ThawBarItems.items(in: .hidden, itemManager: manager, switchedOff: [bundleID])
        #expect(!filtered.contains { $0.tag == alpha.tag }, "a switched-off app stays out")

        let folder = ThawBarItems.items(
            in: .hidden,
            folderMembers: [MenuBarItemTag.canonicalPersistentIdentifier(beta.uniqueIdentifier)],
            itemManager: manager,
            switchedOff: []
        )
        #expect(folder.map(\.tag) == [beta.tag])
    }

    // MARK: Always Hidden only

    @Test("Thaw 2's useThawBarForAlwaysHidden is read back, and a missing one is off")
    func alwaysHiddenOnlyDecodes() throws {
        let thaw2 = Data(#"{"useIceBar":false,"useThawBarForAlwaysHidden":true,"iceBarLocation":0,"alwaysShowHiddenItems":false}"#.utf8)
        #expect(try JSONDecoder().decode(DisplayThawBarConfiguration.self, from: thaw2).useThawBarForAlwaysHidden)
        let thaw3 = Data(#"{"useIceBar":false,"iceBarLocation":0,"alwaysShowHiddenItems":false}"#.utf8)
        #expect(try !JSONDecoder().decode(DisplayThawBarConfiguration.self, from: thaw3).useThawBarForAlwaysHidden)
    }

    @Test("The choice is saved under Thaw 2's key and survives every other change")
    func alwaysHiddenOnlyPersists() throws {
        let configuration = DisplayThawBarConfiguration.defaultConfiguration.withUseThawBarForAlwaysHidden(true)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any]
        #expect(encoded?["useThawBarForAlwaysHidden"] as? Bool == true)
        let changed = configuration
            .withUseThawBar(true).withUseThawBar(false)
            .withThawBarLocation(.mousePointer).withAlwaysShowHiddenItems(true)
            .withThawBarLayout(.grid).withGridColumns(6).withItemSpacingOffset(3).withThawBarItemScale(0.8)
        #expect(changed.useThawBarForAlwaysHidden, "no other setter drops it")
    }

    // MARK: thaw:// per-display table

    @Test("Each per-display key sets, toggles and clamps its value, and a bad value changes nothing")
    func uriTable() {
        let base = DisplayThawBarConfiguration.defaultConfiguration
        func apply(_ key: String, _ info: [AnyHashable: Any]) -> DisplayThawBarConfiguration? {
            DisplaySettingsManager.update(forKey: key, userInfo: info).map { $0(base) }
        }
        #expect(apply("useThawBar", ["value": true])?.useThawBar == true)
        #expect(apply("useThawBar", ["toggle": true])?.useThawBar == !base.useThawBar)
        #expect(apply("useThawBarForAlwaysHidden", ["toggle": true])?.useThawBarForAlwaysHidden == true)
        #expect(apply("gridColumns", ["stringValue": "40"])?.gridColumns == 10)
        #expect(apply("thawBarItemScale", ["stringValue": "0.1"])?.thawBarItemScale == ThawBarItemSize.minimumScale)
        #expect(apply("itemSpacingOffset", ["stringValue": "-40"])?.itemSpacingOffset == -16)
        #expect(apply("thawBarLayout", ["stringValue": "grid"])?.thawBarLayout == .grid)
        #expect(apply("thawBarLocation", ["stringValue": "1"])?.thawBarLocation == .mousePointer)
        #expect(apply("gridColumns", ["stringValue": "many"]) == nil)
        #expect(apply("itemSpacingOffset", ["stringValue": "nan"]) == nil, "clamping would turn it into -16")
        #expect(apply("itemSpacingOffset", ["stringValue": "inf"]) == nil)
        #expect(apply("thawBarItemScale", ["stringValue": "nan"]) == nil)
        #expect(apply("useThawBar", [:]) == nil)
        #expect(apply("unknown", ["value": true]) == nil)
    }

    @Test("The handler accepts and reports the new keys, and refuses bad values")
    func uriParsing() {
        #expect(SettingsURIHandler.perDisplayKeys.contains("thawBarItemScale"))
        #expect(SettingsURIHandler.perDisplayKeys.contains("itemSpacingOffset"))
        #expect(SettingsURIHandler.perDisplayKeys.contains("useThawBarForAlwaysHidden"))
        #expect(!SettingsURIHandler.handlePerDisplaySet(key: "thawBarItemScale", value: "big", displayUUID: nil))
        #expect(!SettingsURIHandler.handlePerDisplaySet(key: "thawBarItemScale", value: "nan", displayUUID: nil))
        #expect(!SettingsURIHandler.handlePerDisplaySet(key: "itemSpacingOffset", value: "nan", displayUUID: nil))
        #expect(!SettingsURIHandler.handlePerDisplaySet(key: "itemSpacingOffset", value: "-inf", displayUUID: nil))
        #expect(!SettingsURIHandler.handlePerDisplaySet(key: "useThawBarForAlwaysHidden", value: "maybe", displayUUID: nil))
        #expect(!SettingsURIHandler.handlePerDisplaySet(key: "notAKey", value: "1", displayUUID: nil))
        let config = DisplayThawBarConfiguration.defaultConfiguration.withThawBarItemScale(0.8)
        #expect(PerDisplayURIKeys.key("thawBarItemScale")?.reading(config)["value"] as? Double == 0.8)
        #expect(PerDisplayURIKeys.key("gridColumns")?.reading(config)["value"] as? Int == config.gridColumns)
    }

    @Test("Each per-display key keeps the default displays and the forwarded value it always had")
    func uriKeyTable() {
        let scopes = Dictionary(uniqueKeysWithValues: PerDisplayURIKeys.all.map { ($0.name, $0.defaultScope) })
        #expect(scopes == [
            "useThawBar": .activeDisplay, "itemSpacingOffset": .activeDisplay,
            "alwaysShowHiddenItems": .allNonThawBarDisplays, "useThawBarForAlwaysHidden": .allNonThawBarDisplays,
            "thawBarLocation": .allEnabledDisplays, "thawBarLayout": .allEnabledDisplays,
            "gridColumns": .allEnabledDisplays, "thawBarItemScale": .allEnabledDisplays,
        ])
        #expect(SettingsURIHandler.perDisplayKeys == [
            "useThawBar", "thawBarLocation", "alwaysShowHiddenItems", "thawBarLayout",
            "gridColumns", "thawBarItemScale", "itemSpacingOffset", "useThawBarForAlwaysHidden",
        ])
        #expect(PerDisplayURIKeys.all.filter(\.isFlag).map(\.name) == ["useThawBar", "alwaysShowHiddenItems", "useThawBarForAlwaysHidden"])

        func forwarded(_ key: String, _ value: String) -> String? {
            guard case let .value(accept, _, _) = PerDisplayURIKeys.key(key)?.kind else { return nil }
            return accept(value)
        }
        #expect(forwarded("thawBarLocation", "iceIcon") == "2")
        #expect(forwarded("thawBarLocation", "rightAligned") == "4")
        #expect(forwarded("thawBarLocation", "sideways") == nil)
        #expect(forwarded("thawBarLayout", "grid") == "2")
        #expect(forwarded("gridColumns", "40") == "10")
        #expect(forwarded("gridColumns", "many") == nil)
        #expect(forwarded("thawBarItemScale", "0.8") == "0.8")
        #expect(forwarded("itemSpacingOffset", "3.4") == "3.0")
        #expect(forwarded("itemSpacingOffset", "-40") == "-16.0")
        #expect(forwarded("useThawBar", "true") == nil, "a Boolean key forwards a flag, not text")
    }

    @Test("A display listing reports every per-display key, and a location lists every place it can be")
    func uriReadings() throws {
        let config = DisplayThawBarConfiguration.defaultConfiguration.withThawBarLocation(.leftAligned).withGridColumns(6)
        let values = PerDisplayURIKeys.values(of: config)
        #expect(Set(values.keys) == Set(SettingsURIHandler.perDisplayKeys))
        #expect(values["thawBarLocation"] as? String == "leftAligned")
        #expect(values["gridColumns"] as? Int == 6)
        #expect(values["useThawBar"] as? Bool == false)

        let location = try #require(PerDisplayURIKeys.key("thawBarLocation")).reading(config)
        #expect(location["rawValue"] as? Int == ThawBarLocation.leftAligned.rawValue)
        #expect(location["validValues"] as? [String: Int] == ["dynamic": 0, "mousePointer": 1, "thawIcon": 2, "leftAligned": 3, "rightAligned": 4])
    }

    // MARK: Displays

    @Test("A saved display without a name is listed by its UUID, and forgetting removes its settings")
    func savedDisplays() {
        let manager = DisplaySettingsManager()
        let named = "AAAAAAAA-0000-0000-0000-000000000001"
        let unnamed = "BBBBBBBB-0000-0000-0000-000000000002"
        manager.knownDisplays = [named: KnownDisplay(name: "Studio Display", hasNotch: false)]
        manager.configurations = [
            named: .defaultConfiguration.withUseThawBar(true),
            unnamed: .defaultConfiguration.withGridColumns(6),
        ]

        let saved = manager.displays.filter { !$0.isConnected }
        #expect(saved.map(\.id).sorted() == [named, unnamed])
        #expect(saved.first { $0.id == unnamed }?.name == DisplaySettingsManager.unnamedDisplayName(uuid: unnamed))
        #expect(DisplaySettingsManager.unnamedDisplayName(uuid: unnamed).contains("BBBBBBBB"))

        manager.forgetDisplay(uuid: named)
        #expect(manager.configurations[named] == nil)
        #expect(manager.knownDisplays[named] == nil)
        #expect(manager.configurations[unnamed] != nil, "other displays stay")
    }

    // MARK: Notch overflow

    @Test("Thaw 2's notch overflow choice is read back, and thaw:// changes it")
    func notchOverflow() {
        Defaults.set(false, forKey: .useThawBarOnNotchOverflow)
        let settings = ThawBarSettings()
        settings.loadInitialState()
        #expect(!settings.useThawBarOnNotchOverflow)
        settings.useThawBarOnNotchOverflow = true
        #expect(Defaults.bool(forKey: .useThawBarOnNotchOverflow))
        #expect(SettingsURIHandler.keyTable["useThawBarOnNotchOverflow"] != nil)
    }
}
