//
//  MenuBarAppearanceConfigurationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
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

    // MARK: - MenuBarAppearanceBorderTests

    /// Tests for the border flags on ``MenuBarAppearancePartialConfiguration``,
    /// which the menu bar and the Thaw Bar read separately.
    @Suite("Border flags")
    struct MenuBarAppearanceBorderTests {
        private func partialConfiguration(
            borderOnMenuBar: Bool,
            borderOnThawBar: Bool
        ) -> MenuBarAppearancePartialConfiguration {
            var partial = MenuBarAppearancePartialConfiguration.defaultConfiguration
            partial.borderOnMenuBar = borderOnMenuBar
            partial.borderOnThawBar = borderOnThawBar
            return partial
        }

        @Test(
            "hasBorder is on when either place draws one",
            arguments: [
                (false, false, false),
                (true, false, true),
                (false, true, true),
                (true, true, true),
            ]
        )
        func hasBorderReflectsBothFlags(menuBar: Bool, thawBar: Bool, expected: Bool) {
            let partial = partialConfiguration(borderOnMenuBar: menuBar, borderOnThawBar: thawBar)

            #expect(partial.hasBorder == expected)
        }

        @Test("Setting hasBorder writes both flags", arguments: [true, false])
        func settingHasBorderWritesBothFlags(newValue: Bool) {
            var partial = MenuBarAppearancePartialConfiguration.defaultConfiguration
            partial.hasBorder = newValue

            #expect(partial.borderOnMenuBar == newValue)
            #expect(partial.borderOnThawBar == newValue)
        }

        @Test("Both flags survive a round trip")
        func encodeDecode() throws {
            let original = partialConfiguration(borderOnMenuBar: false, borderOnThawBar: true)

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(MenuBarAppearancePartialConfiguration.self, from: data)

            #expect(!decoded.borderOnMenuBar)
            #expect(decoded.borderOnThawBar)
        }

        /// Settings saved before the split carry only `hasBorder`, which drew a
        /// border in both places, so it has to seed both flags.
        @Test("A pre-split payload turns the border on in both places", arguments: [true, false])
        func decodeLegacyPayload(legacyHasBorder: Bool) throws {
            let json = Data("{\"hasBorder\": \(legacyHasBorder)}".utf8)

            let decoded = try JSONDecoder().decode(MenuBarAppearancePartialConfiguration.self, from: json)

            #expect(decoded.borderOnMenuBar == legacyHasBorder)
            #expect(decoded.borderOnThawBar == legacyHasBorder)
        }

        /// The new keys win over the legacy one, which is written on every encode
        /// so that older builds still see a border.
        @Test("The split keys take precedence over the legacy one")
        func decodePayloadWithBothKeys() throws {
            let json = Data("""
            {
                "hasBorder": true,
                "borderOnMenuBar": false,
                "borderOnThawBar": true
            }
            """.utf8)

            let decoded = try JSONDecoder().decode(MenuBarAppearancePartialConfiguration.self, from: json)

            #expect(!decoded.borderOnMenuBar)
            #expect(decoded.borderOnThawBar)
        }

        /// Downgrade safety: a build that only knows `hasBorder` has to keep
        /// showing a border for someone who enabled it on just one of the two.
        @Test("Encoding keeps the legacy key for older builds")
        func encodeKeepsLegacyKey() throws {
            let original = partialConfiguration(borderOnMenuBar: false, borderOnThawBar: true)

            let data = try JSONEncoder().encode(original)
            let object = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any]
            )

            #expect(object["hasBorder"] as? Bool == true)
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
                // V1 had a single border flag covering both places.
                #expect(partial.borderOnMenuBar)
                #expect(partial.borderOnThawBar)
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

    /// The Thaw Bar borrowed the menu bar's shape, tint and border for its
    /// whole life before this, so the tests that matter here are the ones
    /// pinning that it still does until someone opts out.
    @MainActor
    @Suite("Thaw Bar appearance")
    struct ThawBarAppearanceTests {
        @Test("The Thaw Bar follows the menu bar by default")
        func defaultDoesNotOverride() {
            #expect(!ThawBarAppearance.defaultConfiguration.overridesMenuBar)
            #expect(!MenuBarAppearanceConfigurationV2.defaultConfiguration.thawBarAppearance.overridesMenuBar)
        }

        @Test("Without an override the menu bar's values are used")
        func inheritsFromMenuBar() {
            let configuration = withMutableCopy(of: MenuBarAppearanceConfigurationV2.defaultConfiguration) { config in
                config.shapeKind = .full
                config.staticConfiguration.tintKind = .solid
                config.staticConfiguration.tintColor = .white
                config.staticConfiguration.borderOnThawBar = true
                config.staticConfiguration.borderWidth = 3
            }

            let resolved = configuration.resolvedThawBarAppearance

            #expect(resolved.hasRoundedShape)
            #expect(resolved.tintKind == .solid)
            #expect(resolved.tintColor == CGColor.white)
            #expect(resolved.hasBorder)
            #expect(resolved.borderWidth == 3)
        }

        /// `MenuBarItemContainer` hardcoded this opacity, so reading the menu
        /// bar's `tintOpacity` instead would restyle every existing install.
        @Test("The inherited tint keeps its own opacity")
        func inheritedTintOpacityIgnoresMenuBar() {
            let configuration = withMutableCopy(of: MenuBarAppearanceConfigurationV2.defaultConfiguration) { config in
                config.staticConfiguration.tintKind = .solid
                config.staticConfiguration.tintOpacity = 0.9
            }

            #expect(configuration.resolvedThawBarAppearance.tintOpacity == ThawBarAppearance.inheritedTintOpacity)
        }

        /// The border is the one property that was already forked, so the menu
        /// bar's own `borderOnMenuBar` must not leak into the panel.
        @Test("A menu-bar-only border does not reach the Thaw Bar")
        func menuBarOnlyBorderIsNotInherited() {
            let configuration = withMutableCopy(of: MenuBarAppearanceConfigurationV2.defaultConfiguration) { config in
                config.staticConfiguration.borderOnMenuBar = true
                config.staticConfiguration.borderOnThawBar = false
            }

            #expect(!configuration.resolvedThawBarAppearance.hasBorder)
        }

        @Test("An override replaces every menu bar value")
        func overrideWins() {
            let configuration = withMutableCopy(of: MenuBarAppearanceConfigurationV2.defaultConfiguration) { config in
                config.shapeKind = .full
                config.staticConfiguration.tintKind = .solid
                config.staticConfiguration.tintColor = .white
                config.staticConfiguration.borderOnThawBar = true
                config.thawBarAppearance = ThawBarAppearance(
                    overridesMenuBar: true,
                    hasRoundedShape: false,
                    tintKind: .solid,
                    tintColor: .black,
                    tintGradient: .defaultMenuBarTint,
                    tintOpacity: 0.75,
                    hasBorder: false,
                    borderColor: .black,
                    borderWidth: 2
                )
            }

            let resolved = configuration.resolvedThawBarAppearance

            #expect(!resolved.hasRoundedShape)
            #expect(resolved.tintColor == CGColor.black)
            #expect(resolved.tintOpacity == 0.75)
            #expect(!resolved.hasBorder)
        }

        /// Switching the toggle on is meant to change nothing until something
        /// is edited, which only holds if the seed round trips exactly.
        @Test("Seeding an override changes nothing on screen")
        func seedingIsInert() {
            let configuration = withMutableCopy(of: MenuBarAppearanceConfigurationV2.defaultConfiguration) { config in
                config.shapeKind = .full
                config.staticConfiguration.tintKind = .gradient
                config.staticConfiguration.borderOnThawBar = true
                config.staticConfiguration.borderWidth = 3
            }
            let before = configuration.resolvedThawBarAppearance

            let seeded = withMutableCopy(of: configuration) { config in
                config.thawBarAppearance = ThawBarAppearance(seededFrom: before)
            }

            #expect(seeded.resolvedThawBarAppearance == before)
        }

        /// The panel has never drawn the wallpaper-derived kinds, so seeding
        /// one would hand the editor a selection it cannot render.
        @Test("Seeding drops a tint kind the Thaw Bar cannot draw")
        func seedingDropsUnsupportedTintKind() {
            let configuration = withMutableCopy(of: MenuBarAppearanceConfigurationV2.defaultConfiguration) { config in
                config.staticConfiguration.tintKind = .adaptive
            }

            let seeded = ThawBarAppearance(seededFrom: configuration.resolvedThawBarAppearance)

            #expect(seeded.tintKind == .noTint)
        }

        // MARK: - Codable

        @Test("An override survives a round trip")
        func encodeDecode() throws {
            let original = ThawBarAppearance(
                overridesMenuBar: true,
                hasRoundedShape: true,
                tintKind: .solid,
                tintColor: .white,
                tintGradient: .defaultMenuBarTint,
                tintOpacity: 0.45,
                hasBorder: true,
                borderColor: .white,
                borderWidth: 3
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ThawBarAppearance.self, from: data)

            #expect(decoded == original)
        }

        /// Configurations written before this existed have no key for it, and
        /// must keep following the menu bar rather than picking up a fork.
        @Test("A configuration saved before the fork keeps following the menu bar")
        func decodeWithMissingField() throws {
            let data = Data("{}".utf8)

            let decoded = try JSONDecoder().decode(MenuBarAppearanceConfigurationV2.self, from: data)

            #expect(!decoded.thawBarAppearance.overridesMenuBar)
        }
    }
}
