//
//  MenuBarAppearanceConfigurationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Menu bar appearance configuration")
struct MenuBarAppearanceConfigurationTests {
    @Suite("MenuBarAppearanceConfigurationV2")
    struct MenuBarAppearanceConfigurationV2Tests {
        // MARK: - Default Configuration Tests

        @Test("The default configuration ships the documented values")
        func defaultConfiguration() {
            let config = MenuBarAppearanceConfigurationV2.defaultConfiguration

            #expect(config.shapeKind == .noShape)
            #expect(config.isInset)
            #expect(config.leftMargin == 0)
            #expect(config.rightMargin == 0)
            #expect(!config.isDynamic)
        }

        // MARK: - Has Rounded Shape Tests

        @Test("A configuration with no shape has no rounded shape")
        func hasRoundedShapeNoShape() {
            var config = MenuBarAppearanceConfigurationV2.defaultConfiguration
            config.shapeKind = .noShape

            #expect(!config.hasRoundedShape)
        }

        // MARK: - Codable Tests

        @Test("The default configuration survives a round trip")
        func encodeDecode() throws {
            let original = MenuBarAppearanceConfigurationV2.defaultConfiguration

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)

            #expect(decoded.shapeKind == original.shapeKind)
            #expect(decoded.isInset == original.isInset)
            #expect(decoded.leftMargin == original.leftMargin)
            #expect(decoded.rightMargin == original.rightMargin)
            #expect(decoded.isDynamic == original.isDynamic)
        }

        @Test("An empty payload decodes to the defaults")
        func decodeWithMissingFields() throws {
            // Test forward compatibility - decode with minimal JSON
            let json = "{}".data(using: .utf8)!

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: json)

            // Should use default values for missing fields
            let defaultConfig = MenuBarAppearanceConfigurationV2.defaultConfiguration
            #expect(decoded.shapeKind == defaultConfig.shapeKind)
            #expect(decoded.isInset == defaultConfig.isInset)
        }

        @Test("A partial payload decodes its own fields and defaults the rest")
        func decodeWithPartialFields() throws {
            let json = """
            {
                "isDynamic": true,
                "leftMargin": 10.0,
                "rightMargin": 5.0
            }
            """.data(using: .utf8)!

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: json)

            #expect(decoded.isDynamic)
            #expect(decoded.leftMargin == 10.0)
            #expect(decoded.rightMargin == 5.0)
            // Other fields should have defaults
            #expect(decoded.shapeKind == .noShape)
        }

        // MARK: - Hashable Tests

        @Test("Two default configurations hash alike")
        func hashableIdentical() {
            let config1 = MenuBarAppearanceConfigurationV2.defaultConfiguration
            let config2 = MenuBarAppearanceConfigurationV2.defaultConfiguration

            #expect(config1.hashValue == config2.hashValue)
        }
    }

    // MARK: - MenuBarAppearanceV1MigrationTests

    /// Tests for converting V1 appearance data — the format Ice used before its
    /// `0.11.10` release — which reaches Thaw only through the Ice importer.
    ///
    /// `MenuBarAppearanceConfigurationV1` is main-actor isolated, as is the
    /// importer that reads it, so these tests are too.
    @MainActor
    @Suite("V1 migration")
    struct MenuBarAppearanceV1MigrationTests {
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
        @Test("Migrated values apply to every appearance")
        func migratedValuesApplyToEveryAppearance() {
            let configuration = MenuBarAppearanceConfigurationV2(migrating: oldConfiguration)
            let partials = [
                configuration.lightModeConfiguration,
                configuration.darkModeConfiguration,
                configuration.staticConfiguration,
            ]

            for partial in partials {
                #expect(partial.hasShadow)
                #expect(partial.hasBorder)
                #expect(partial.borderWidth == 3)
                #expect(partial.tintKind == .solid)
            }
        }

        /// Shape and inset sit on the configuration itself in both formats.
        @Test("Shape and inset are carried across")
        func migratedShapeAndInset() {
            let configuration = MenuBarAppearanceConfigurationV2(migrating: oldConfiguration)

            #expect(configuration.shapeKind == .full)
            #expect(!configuration.isInset)
        }

        /// V1 had no background, opacity, or notch values, so those keep the
        /// current defaults rather than being zeroed out.
        @Test("Values absent from V1 keep the current defaults")
        func valuesAbsentFromV1KeepDefaults() {
            let configuration = MenuBarAppearanceConfigurationV2(migrating: oldConfiguration)
            let defaultConfiguration = MenuBarAppearanceConfigurationV2.defaultConfiguration
            let defaultPartial = MenuBarAppearancePartialConfiguration.defaultConfiguration

            #expect(configuration.staticConfiguration.backgroundKind == defaultPartial.backgroundKind)
            #expect(configuration.staticConfiguration.tintOpacity == defaultPartial.tintOpacity)
            #expect(configuration.staticConfiguration.backgroundOpacity == defaultPartial.backgroundOpacity)
            #expect(configuration.notchShapeInfo == defaultConfiguration.notchShapeInfo)
            #expect(configuration.isDynamic == defaultConfiguration.isDynamic)
        }
    }
}
