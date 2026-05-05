//
//  DisplayIceBarConfigurationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class DisplayIceBarConfigurationTests: XCTestCase {
    // MARK: - Default Configuration Tests

    func testDefaultConfiguration() {
        let config = DisplayIceBarConfiguration.defaultConfiguration

        XCTAssertFalse(config.useIceBar)
        XCTAssertEqual(config.iceBarLocation, .dynamic)
        XCTAssertFalse(config.alwaysShowHiddenItems)
        XCTAssertEqual(config.iceBarLayout, .horizontal)
        XCTAssertEqual(config.gridColumns, 4)
        XCTAssertEqual(config.itemSpacingOffset, 0)
    }

    // MARK: - Initialization Tests

    func testCustomInitialization() {
        let config = DisplayIceBarConfiguration(
            useIceBar: true,
            iceBarLocation: .mousePointer,
            alwaysShowHiddenItems: true,
            iceBarLayout: .grid,
            gridColumns: 6,
            itemSpacingOffset: 5.0
        )

        XCTAssertTrue(config.useIceBar)
        XCTAssertEqual(config.iceBarLocation, .mousePointer)
        XCTAssertTrue(config.alwaysShowHiddenItems)
        XCTAssertEqual(config.iceBarLayout, .grid)
        XCTAssertEqual(config.gridColumns, 6)
        XCTAssertEqual(config.itemSpacingOffset, 5.0)
    }

    // MARK: - With Methods Tests

    func testWithUseIceBar() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withUseIceBar(true)

        XCTAssertTrue(modified.useIceBar)
        XCTAssertEqual(modified.iceBarLocation, original.iceBarLocation)
        XCTAssertEqual(modified.alwaysShowHiddenItems, original.alwaysShowHiddenItems)
        XCTAssertEqual(modified.iceBarLayout, original.iceBarLayout)
        XCTAssertEqual(modified.gridColumns, original.gridColumns)
    }

    func testWithUseIceBarDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withUseIceBar(true)

        XCTAssertFalse(original.useIceBar)
    }

    func testWithIceBarLocation() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withIceBarLocation(.iceIcon)

        XCTAssertEqual(modified.iceBarLocation, .iceIcon)
        XCTAssertEqual(modified.useIceBar, original.useIceBar)
        XCTAssertEqual(modified.alwaysShowHiddenItems, original.alwaysShowHiddenItems)
        XCTAssertEqual(modified.iceBarLayout, original.iceBarLayout)
        XCTAssertEqual(modified.gridColumns, original.gridColumns)
    }

    func testWithIceBarLocationDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withIceBarLocation(.mousePointer)

        XCTAssertEqual(original.iceBarLocation, .dynamic)
    }

    func testWithAlwaysShowHiddenItems() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withAlwaysShowHiddenItems(true)

        XCTAssertTrue(modified.alwaysShowHiddenItems)
        XCTAssertEqual(modified.useIceBar, original.useIceBar)
        XCTAssertEqual(modified.iceBarLocation, original.iceBarLocation)
        XCTAssertEqual(modified.iceBarLayout, original.iceBarLayout)
        XCTAssertEqual(modified.gridColumns, original.gridColumns)
    }

    func testWithAlwaysShowHiddenItemsDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withAlwaysShowHiddenItems(true)

        XCTAssertFalse(original.alwaysShowHiddenItems)
    }

    func testWithIceBarLayout() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withIceBarLayout(.vertical)

        XCTAssertEqual(modified.iceBarLayout, .vertical)
        XCTAssertEqual(modified.useIceBar, original.useIceBar)
        XCTAssertEqual(modified.iceBarLocation, original.iceBarLocation)
        XCTAssertEqual(modified.alwaysShowHiddenItems, original.alwaysShowHiddenItems)
        XCTAssertEqual(modified.gridColumns, original.gridColumns)
    }

    func testWithIceBarLayoutDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withIceBarLayout(.grid)

        XCTAssertEqual(original.iceBarLayout, .horizontal)
    }

    func testWithGridColumns() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withGridColumns(8)

        XCTAssertEqual(modified.gridColumns, 8)
        XCTAssertEqual(modified.useIceBar, original.useIceBar)
        XCTAssertEqual(modified.iceBarLocation, original.iceBarLocation)
        XCTAssertEqual(modified.alwaysShowHiddenItems, original.alwaysShowHiddenItems)
        XCTAssertEqual(modified.iceBarLayout, original.iceBarLayout)
    }

    func testWithGridColumnsClamping() {
        let original = DisplayIceBarConfiguration.defaultConfiguration

        let tooLow = original.withGridColumns(0)
        XCTAssertEqual(tooLow.gridColumns, 2)

        let tooHigh = original.withGridColumns(20)
        XCTAssertEqual(tooHigh.gridColumns, 10)

        let normal = original.withGridColumns(5)
        XCTAssertEqual(normal.gridColumns, 5)
    }

    func testWithGridColumnsDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withGridColumns(7)

        XCTAssertEqual(original.gridColumns, 4)
    }

    func testWithItemSpacingOffset() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        let modified = original.withItemSpacingOffset(8)

        XCTAssertEqual(modified.itemSpacingOffset, 8)
        XCTAssertEqual(modified.useIceBar, original.useIceBar)
        XCTAssertEqual(modified.iceBarLocation, original.iceBarLocation)
        XCTAssertEqual(modified.alwaysShowHiddenItems, original.alwaysShowHiddenItems)
        XCTAssertEqual(modified.iceBarLayout, original.iceBarLayout)
        XCTAssertEqual(modified.gridColumns, original.gridColumns)
    }

    func testWithItemSpacingOffsetNegative() {
        let modified = DisplayIceBarConfiguration.defaultConfiguration
            .withItemSpacingOffset(-10)

        XCTAssertEqual(modified.itemSpacingOffset, -10)
    }

    func testWithItemSpacingOffsetFractional() {
        let modified = DisplayIceBarConfiguration.defaultConfiguration
            .withItemSpacingOffset(2.5)

        XCTAssertEqual(modified.itemSpacingOffset, 2.5, accuracy: 0.001)
    }

    func testWithItemSpacingOffsetClamping() {
        let original = DisplayIceBarConfiguration.defaultConfiguration

        let tooLow = original.withItemSpacingOffset(-100)
        XCTAssertEqual(tooLow.itemSpacingOffset, -16)

        let tooHigh = original.withItemSpacingOffset(100)
        XCTAssertEqual(tooHigh.itemSpacingOffset, 16)

        let inRange = original.withItemSpacingOffset(7.5)
        XCTAssertEqual(inRange.itemSpacingOffset, 7.5, accuracy: 0.001)
    }

    func testWithItemSpacingOffsetDoesNotMutateOriginal() {
        let original = DisplayIceBarConfiguration.defaultConfiguration
        _ = original.withItemSpacingOffset(10)

        XCTAssertEqual(original.itemSpacingOffset, 0)
    }

    // MARK: - Chained With Methods

    func testChainedWithMethods() {
        let config = DisplayIceBarConfiguration.defaultConfiguration
            .withUseIceBar(true)
            .withIceBarLocation(.iceIcon)
            .withAlwaysShowHiddenItems(true)
            .withIceBarLayout(.grid)
            .withGridColumns(5)
            .withItemSpacingOffset(-3)

        XCTAssertTrue(config.useIceBar)
        XCTAssertEqual(config.iceBarLocation, .iceIcon)
        XCTAssertTrue(config.alwaysShowHiddenItems)
        XCTAssertEqual(config.iceBarLayout, .grid)
        XCTAssertEqual(config.gridColumns, 5)
        XCTAssertEqual(config.itemSpacingOffset, -3)
    }

    // MARK: - Equatable Tests

    func testEquatableIdentical() {
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

        XCTAssertEqual(config1, config2)
    }

    func testEquatableDifferentUseIceBar() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withUseIceBar(true)

        XCTAssertNotEqual(config1, config2)
    }

    func testEquatableDifferentLocation() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withIceBarLocation(.iceIcon)

        XCTAssertNotEqual(config1, config2)
    }

    func testEquatableDifferentAlwaysShow() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withAlwaysShowHiddenItems(true)

        XCTAssertNotEqual(config1, config2)
    }

    func testEquatableDifferentLayout() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withIceBarLayout(.grid)

        XCTAssertNotEqual(config1, config2)
    }

    func testEquatableDifferentGridColumns() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withGridColumns(6)

        XCTAssertNotEqual(config1, config2)
    }

    func testEquatableDifferentItemSpacingOffset() {
        let config1 = DisplayIceBarConfiguration.defaultConfiguration
        let config2 = config1.withItemSpacingOffset(5)

        XCTAssertNotEqual(config1, config2)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
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

        XCTAssertEqual(decoded, original)
    }

    func testEncodeDecodeDefaultConfiguration() throws {
        let original = DisplayIceBarConfiguration.defaultConfiguration

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DisplayIceBarConfiguration.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDecodeFromJSON() throws {
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

        XCTAssertTrue(decoded.useIceBar)
        XCTAssertEqual(decoded.iceBarLocation, .iceIcon)
        XCTAssertFalse(decoded.alwaysShowHiddenItems)
        XCTAssertEqual(decoded.iceBarLayout, .grid)
        XCTAssertEqual(decoded.gridColumns, 5)
    }

    func testDecodeOldJSONWithoutNewFields() throws {
        let json = """
        {
            "useIceBar": true,
            "iceBarLocation": 1,
            "alwaysShowHiddenItems": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DisplayIceBarConfiguration.self, from: json)

        XCTAssertTrue(decoded.useIceBar)
        XCTAssertEqual(decoded.iceBarLocation, .mousePointer)
        XCTAssertFalse(decoded.alwaysShowHiddenItems)
        XCTAssertEqual(decoded.iceBarLayout, .horizontal)
        XCTAssertEqual(decoded.gridColumns, 4)
        XCTAssertEqual(decoded.itemSpacingOffset, 0)
    }

    func testDecodeOldJSONWithInvalidGridColumns() throws {
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

        XCTAssertEqual(decoded.gridColumns, 10)
    }

    func testDecodeJSONWithItemSpacingOffset() throws {
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

        XCTAssertEqual(decoded.itemSpacingOffset, -7.5, accuracy: 0.001)
    }

    func testDecodeJSONClampsOutOfRangeItemSpacingOffset() throws {
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

        XCTAssertEqual(decoded.itemSpacingOffset, 16)
    }

    // MARK: - All Locations Tests

    func testAllIceBarLocations() {
        for location in IceBarLocation.allCases {
            let config = DisplayIceBarConfiguration.defaultConfiguration.withIceBarLocation(location)
            XCTAssertEqual(config.iceBarLocation, location)
        }
    }

    // MARK: - All Layout Tests

    func testAllIceBarLayouts() {
        for layout in IceBarLayout.allCases {
            let config = DisplayIceBarConfiguration.defaultConfiguration.withIceBarLayout(layout)
            XCTAssertEqual(config.iceBarLayout, layout)
        }
    }
}
