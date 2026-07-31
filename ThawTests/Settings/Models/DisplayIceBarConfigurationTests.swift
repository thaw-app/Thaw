//
//  DisplayIceBarConfigurationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Display Ice Bar configuration")
struct DisplayIceBarConfigurationTests {
    // MARK: - Default Configuration Tests

    @Test("The default configuration ships the documented values")
    func defaultConfiguration() {
        let config = DisplayIceBarConfiguration.defaultConfiguration

        #expect(!config.useIceBar)
        #expect(config.iceBarLocation == .dynamic)
        #expect(!config.alwaysShowHiddenItems)
        #expect(config.iceBarLayout == .horizontal)
        #expect(config.gridColumns == 4)
        #expect(config.itemSpacingOffset == 0)
    }

    // MARK: - Initialization Tests

    @Test("The memberwise initializer keeps every value it is given")
    func customInitialization() {
        let config = DisplayIceBarConfiguration(
            useIceBar: true,
            iceBarLocation: .mousePointer,
            alwaysShowHiddenItems: true,
            iceBarLayout: .grid,
            gridColumns: 6,
            itemSpacingOffset: 5.0
        )

        #expect(config.useIceBar)
        #expect(config.iceBarLocation == .mousePointer)
        #expect(config.alwaysShowHiddenItems)
        #expect(config.iceBarLayout == .grid)
        #expect(config.gridColumns == 6)
        #expect(config.itemSpacingOffset == 5.0)
    }

    // MARK: - With Methods Tests

    @Test("withUseIceBar changes only the Ice Bar flag")
    func withUseIceBar() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withUseIceBar(true)

        #expect(modified.useIceBar)
        #expect(modified.iceBarLocation == original.iceBarLocation)
        #expect(modified.alwaysShowHiddenItems == original.alwaysShowHiddenItems)
        #expect(modified.iceBarLayout == original.iceBarLayout)
        #expect(modified.gridColumns == original.gridColumns)
    }

    @Test("withUseIceBar leaves the original alone")
    func withUseIceBarDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withUseIceBar(true)

        #expect(!original.useIceBar)
    }

    @Test("withIceBarLocation changes only the location")
    func withIceBarLocation() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withIceBarLocation(.iceIcon)

        #expect(modified.iceBarLocation == .iceIcon)
        #expect(modified.useIceBar == original.useIceBar)
        #expect(modified.alwaysShowHiddenItems == original.alwaysShowHiddenItems)
        #expect(modified.iceBarLayout == original.iceBarLayout)
        #expect(modified.gridColumns == original.gridColumns)
    }

    @Test("withIceBarLocation leaves the original alone")
    func withIceBarLocationDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withIceBarLocation(.mousePointer)

        #expect(original.iceBarLocation == .dynamic)
    }

    @Test("withAlwaysShowHiddenItems changes only that flag")
    func withAlwaysShowHiddenItems() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withAlwaysShowHiddenItems(true)

        #expect(modified.alwaysShowHiddenItems)
        #expect(modified.useIceBar == original.useIceBar)
        #expect(modified.iceBarLocation == original.iceBarLocation)
        #expect(modified.iceBarLayout == original.iceBarLayout)
        #expect(modified.gridColumns == original.gridColumns)
    }

    @Test("withAlwaysShowHiddenItems leaves the original alone")
    func withAlwaysShowHiddenItemsDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withAlwaysShowHiddenItems(true)

        #expect(!original.alwaysShowHiddenItems)
    }

    @Test("withIceBarLayout changes only the layout")
    func withIceBarLayout() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withIceBarLayout(.vertical)

        #expect(modified.iceBarLayout == .vertical)
        #expect(modified.useIceBar == original.useIceBar)
        #expect(modified.iceBarLocation == original.iceBarLocation)
        #expect(modified.alwaysShowHiddenItems == original.alwaysShowHiddenItems)
        #expect(modified.gridColumns == original.gridColumns)
    }

    @Test("withIceBarLayout leaves the original alone")
    func withIceBarLayoutDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withIceBarLayout(.grid)

        #expect(original.iceBarLayout == .horizontal)
    }

    @Test("withGridColumns changes only the column count")
    func withGridColumns() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withGridColumns(8)

        #expect(modified.gridColumns == 8)
        #expect(modified.useIceBar == original.useIceBar)
        #expect(modified.iceBarLocation == original.iceBarLocation)
        #expect(modified.alwaysShowHiddenItems == original.alwaysShowHiddenItems)
        #expect(modified.iceBarLayout == original.iceBarLayout)
    }

    @Test("withGridColumns clamps the column count to its supported range")
    func withGridColumnsClamping() {
        let original = DisplayIceBarConfiguration.defaultConfiguration

        let tooLow = original.withGridColumns(0)
        #expect(tooLow.gridColumns == 2)

        let tooHigh = original.withGridColumns(20)
        #expect(tooHigh.gridColumns == 10)

        let normal = original.withGridColumns(5)
        #expect(normal.gridColumns == 5)
    }

    @Test("withGridColumns leaves the original alone")
    func withGridColumnsDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withGridColumns(7)

        #expect(original.gridColumns == 4)
    }

    @Test("withItemSpacingOffset changes only the spacing offset")
    func withItemSpacingOffset() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withItemSpacingOffset(8)

        #expect(modified.itemSpacingOffset == 8)
        #expect(modified.useIceBar == original.useIceBar)
        #expect(modified.iceBarLocation == original.iceBarLocation)
        #expect(modified.alwaysShowHiddenItems == original.alwaysShowHiddenItems)
        #expect(modified.iceBarLayout == original.iceBarLayout)
        #expect(modified.gridColumns == original.gridColumns)
    }

    @Test("A negative spacing offset is kept")
    func withItemSpacingOffsetNegative() {
        let modified = DisplayIceBarConfiguration.defaultConfiguration
            .withItemSpacingOffset(-10)

        #expect(modified.itemSpacingOffset == -10)
    }

    @Test("A fractional spacing offset is kept")
    func withItemSpacingOffsetFractional() {
        let modified = DisplayIceBarConfiguration.defaultConfiguration
            .withItemSpacingOffset(2.5)

        #expect(abs(modified.itemSpacingOffset - 2.5) < 0.001)
    }

    @Test("withItemSpacingOffset clamps the offset to its supported range")
    func withItemSpacingOffsetClamping() {
        let original = DisplayIceBarConfiguration.defaultConfiguration

        let tooLow = original.withItemSpacingOffset(-100)
        #expect(tooLow.itemSpacingOffset == -16)

        let tooHigh = original.withItemSpacingOffset(100)
        #expect(tooHigh.itemSpacingOffset == 16)

        let inRange = original.withItemSpacingOffset(7.5)
        #expect(abs(inRange.itemSpacingOffset - 7.5) < 0.001)
    }

    @Test("withItemSpacingOffset leaves the original alone")
    func withItemSpacingOffsetDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withItemSpacingOffset(10)

        #expect(original.itemSpacingOffset == 0)
    }

    // MARK: - Chained With Methods

    @Test("Chained with-methods each keep their value")
    func chainedWithMethods() {
        let config = DisplayIceBarConfiguration.defaultConfiguration
            .withUseIceBar(true)
            .withIceBarLocation(.iceIcon)
            .withAlwaysShowHiddenItems(true)
            .withIceBarLayout(.grid)
            .withGridColumns(5)
            .withItemSpacingOffset(-3)

        #expect(config.useIceBar)
        #expect(config.iceBarLocation == .iceIcon)
        #expect(config.alwaysShowHiddenItems)
        #expect(config.iceBarLayout == .grid)
        #expect(config.gridColumns == 5)
        #expect(config.itemSpacingOffset == -3)
    }

    // MARK: - Equatable Tests

    @Test("Two configurations built from the same values are equal")
    func equatableIdentical() {
        let config1 = DisplayIceBarConfiguration(
            useIceBar: true,
            iceBarLocation: .mousePointer,
            alwaysShowHiddenItems: false,
            iceBarLayout: .vertical,
            gridColumns: 3,
            itemSpacingOffset: -4
        )
        let config2 = DisplayIceBarConfiguration(
            useIceBar: true,
            iceBarLocation: .mousePointer,
            alwaysShowHiddenItems: false,
            iceBarLayout: .vertical,
            gridColumns: 3,
            itemSpacingOffset: -4
        )

        #expect(config1 == config2)
    }

    @Test("A different Ice Bar flag makes configurations unequal")
    func equatableDifferentUseIceBar() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withUseIceBar(true)

        #expect(config1 != config2)
    }

    @Test("A different location makes configurations unequal")
    func equatableDifferentLocation() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withIceBarLocation(.iceIcon)

        #expect(config1 != config2)
    }

    @Test("A different always-show flag makes configurations unequal")
    func equatableDifferentAlwaysShow() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withAlwaysShowHiddenItems(true)

        #expect(config1 != config2)
    }

    @Test("A different layout makes configurations unequal")
    func equatableDifferentLayout() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withIceBarLayout(.grid)

        #expect(config1 != config2)
    }

    @Test("A different column count makes configurations unequal")
    func equatableDifferentGridColumns() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withGridColumns(6)

        #expect(config1 != config2)
    }

    @Test("A different spacing offset makes configurations unequal")
    func equatableDifferentItemSpacingOffset() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withItemSpacingOffset(5)

        #expect(config1 != config2)
    }

    // MARK: - Codable Tests

    @Test("A custom configuration survives a round trip")
    func encodeDecode() throws {
        let original = DisplayIceBarConfiguration(
            useIceBar: true,
            iceBarLocation: .iceIcon,
            alwaysShowHiddenItems: true,
            iceBarLayout: .grid,
            gridColumns: 6,
            itemSpacingOffset: 2.5
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DisplayIceBarConfiguration.self, from: data)

        #expect(decoded == original)
    }

    @Test("The default configuration survives a round trip")
    func encodeDecodeDefaultConfiguration() throws {
        let original = DisplayIceBarConfiguration.defaultConfiguration

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DisplayIceBarConfiguration.self, from: data)

        #expect(decoded == original)
    }

    @Test("A full JSON payload decodes into every field")
    func decodeFromJSON() throws {
        let json = """
        {
            "useIceBar": true,
            "iceBarLocation": 2,
            "alwaysShowHiddenItems": false,
            "iceBarLayout": 2,
            "gridColumns": 5
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DisplayIceBarConfiguration.self, from: json)

        #expect(decoded.useIceBar)
        #expect(decoded.iceBarLocation == .iceIcon)
        #expect(!decoded.alwaysShowHiddenItems)
        #expect(decoded.iceBarLayout == .grid)
        #expect(decoded.gridColumns == 5)
    }

    @Test("An older payload without the newer fields falls back to the defaults")
    func decodeOldJSONWithoutNewFields() throws {
        let json = """
        {
            "useIceBar": true,
            "iceBarLocation": 1,
            "alwaysShowHiddenItems": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DisplayIceBarConfiguration.self, from: json)

        #expect(decoded.useIceBar)
        #expect(decoded.iceBarLocation == .mousePointer)
        #expect(!decoded.alwaysShowHiddenItems)
        #expect(decoded.iceBarLayout == .horizontal)
        #expect(decoded.gridColumns == 4)
        #expect(decoded.itemSpacingOffset == 0)
    }

    @Test("An out-of-range stored column count is clamped on decode")
    func decodeOldJSONWithInvalidGridColumns() throws {
        let json = """
        {
            "useIceBar": false,
            "iceBarLocation": 0,
            "alwaysShowHiddenItems": false,
            "iceBarLayout": 1,
            "gridColumns": 50
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DisplayIceBarConfiguration.self, from: json)

        #expect(decoded.gridColumns == 10)
    }

    @Test("A stored spacing offset is decoded")
    func decodeJSONWithItemSpacingOffset() throws {
        let json = """
        {
            "useIceBar": false,
            "iceBarLocation": 0,
            "alwaysShowHiddenItems": false,
            "iceBarLayout": 1,
            "gridColumns": 4,
            "itemSpacingOffset": -7.5
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DisplayIceBarConfiguration.self, from: json)

        #expect(abs(decoded.itemSpacingOffset - -7.5) < 0.001)
    }

    @Test("An out-of-range stored spacing offset is clamped on decode")
    func decodeJSONClampsOutOfRangeItemSpacingOffset() throws {
        let json = """
        {
            "useIceBar": false,
            "iceBarLocation": 0,
            "alwaysShowHiddenItems": false,
            "iceBarLayout": 1,
            "gridColumns": 4,
            "itemSpacingOffset": 99
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DisplayIceBarConfiguration.self, from: json)

        #expect(decoded.itemSpacingOffset == 16)
    }

    // MARK: - All Locations Tests

    @Test("Every location can be set")
    func allIceBarLocations() {
        for location in IceBarLocation.allCases {
            let config = DisplayIceBarConfiguration.defaultConfiguration.withIceBarLocation(location)
            #expect(config.iceBarLocation == location)
        }
    }

    // MARK: - All Layout Tests

    @Test("Every layout can be set")
    func allIceBarLayouts() {
        for layout in IceBarLayout.allCases {
            let config = DisplayIceBarConfiguration.defaultConfiguration.withIceBarLayout(layout)
            #expect(config.iceBarLayout == layout)
        }
    }
}
