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

// MARK: - MenuBarAppearanceV1MigrationTests

/// Tests for converting V1 appearance data — the format Ice used before its
/// `0.11.10` release — which reaches Thaw only through the Ice importer.
///
/// `MenuBarAppearanceConfigurationV1` is main-actor isolated, as is the
/// importer that reads it, so these tests are too.
@MainActor
final class MenuBarAppearanceV1MigrationTests: XCTestCase {
    private var oldConfiguration: MenuBarAppearanceConfigurationV1 {
        withMutableCopy(of: MenuBarAppearanceConfigurationV1.defaultConfiguration) { configuration in
            configuration.hasShadow = true
            configuration.hasBorder = true
            configuration.borderWidth = 3
            configuration.tintKind = .solid
            configuration.shapeKind = .full
            configuration.isInset = false
        }
    }

    /// V1 had one set of values for every system appearance, so all three of
    /// the current configuration's slots receive them.
    func testMigratedValuesApplyToEveryAppearance() {
        let configuration = MenuBarAppearanceConfigurationV2(migrating: oldConfiguration)
        let partials = [
            configuration.lightModeConfiguration,
            configuration.darkModeConfiguration,
            configuration.staticConfiguration,
        ]

        for partial in partials {
            XCTAssertTrue(partial.hasShadow)
            XCTAssertTrue(partial.hasBorder)
            XCTAssertEqual(partial.borderWidth, 3)
            XCTAssertEqual(partial.tintKind, .solid)
        }
    }

    /// Shape and inset sit on the configuration itself in both formats.
    func testMigratedShapeAndInset() {
        let configuration = MenuBarAppearanceConfigurationV2(migrating: oldConfiguration)

        XCTAssertEqual(configuration.shapeKind, .full)
        XCTAssertFalse(configuration.isInset)
    }

    /// V1 had no background, opacity, or notch values, so those keep the
    /// current defaults rather than being zeroed out.
    func testValuesAbsentFromV1KeepDefaults() {
        let configuration = MenuBarAppearanceConfigurationV2(migrating: oldConfiguration)
        let defaultConfiguration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        let defaultPartial = MenuBarAppearancePartialConfiguration.defaultConfiguration

        XCTAssertEqual(configuration.staticConfiguration.backgroundKind, defaultPartial.backgroundKind)
        XCTAssertEqual(configuration.staticConfiguration.tintOpacity, defaultPartial.tintOpacity)
        XCTAssertEqual(configuration.staticConfiguration.backgroundOpacity, defaultPartial.backgroundOpacity)
        XCTAssertEqual(configuration.notchShapeInfo, defaultConfiguration.notchShapeInfo)
        XCTAssertEqual(configuration.isDynamic, defaultConfiguration.isDynamic)
    }
}
