//
//  MenuBarAppearanceConfigurationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class MenuBarAppearanceConfigurationV2Tests: XCTestCase {
    // MARK: - Default Configuration Tests

    func testDefaultConfiguration() {
        let config = MenuBarAppearanceConfigurationV2.defaultConfiguration

        XCTAssertEqual(config.shapeKind, .noShape)
        XCTAssertTrue(config.isInset)
        XCTAssertEqual(config.leftMargin, 0)
        XCTAssertEqual(config.rightMargin, 0)
        XCTAssertFalse(config.isDynamic)
    }

    // MARK: - Has Rounded Shape Tests

    func testHasRoundedShapeNoShape() {
        var config = MenuBarAppearanceConfigurationV2.defaultConfiguration
        config.shapeKind = .noShape

        XCTAssertFalse(config.hasRoundedShape)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let original = MenuBarAppearanceConfigurationV2.defaultConfiguration

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)

        XCTAssertEqual(decoded.shapeKind, original.shapeKind)
        XCTAssertEqual(decoded.isInset, original.isInset)
        XCTAssertEqual(decoded.leftMargin, original.leftMargin)
        XCTAssertEqual(decoded.rightMargin, original.rightMargin)
        XCTAssertEqual(decoded.isDynamic, original.isDynamic)
    }

    func testDecodeWithMissingFields() throws {
        // Test forward compatibility - decode with minimal JSON
        let json = "{}".data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: json)

        // Should use default values for missing fields
        let defaultConfig = MenuBarAppearanceConfigurationV2.defaultConfiguration
        XCTAssertEqual(decoded.shapeKind, defaultConfig.shapeKind)
        XCTAssertEqual(decoded.isInset, defaultConfig.isInset)
    }

    func testDecodeWithPartialFields() throws {
        let json = """
        {
            "isDynamic": true,
            "leftMargin": 10.0,
            "rightMargin": 5.0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: json)

        XCTAssertTrue(decoded.isDynamic)
        XCTAssertEqual(decoded.leftMargin, 10.0)
        XCTAssertEqual(decoded.rightMargin, 5.0)
        // Other fields should have defaults
        XCTAssertEqual(decoded.shapeKind, .noShape)
    }

    // MARK: - Hashable Tests

    func testHashableIdentical() {
        let config1 = MenuBarAppearanceConfigurationV2.defaultConfiguration
        let config2 = MenuBarAppearanceConfigurationV2.defaultConfiguration

        XCTAssertEqual(config1.hashValue, config2.hashValue)
    }
}
