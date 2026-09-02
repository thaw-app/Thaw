//
//  ThawBarAppearanceConfigurationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@Suite("Thaw Bar appearance configuration")
struct ThawBarAppearanceConfigurationTests {
    @Suite("Kinds")
    struct KindTests {
        @Test("Background kind raw values stay stable for persistence", arguments: [
            (ThawBarBackgroundKind.adaptive, 0),
            (.solid, 1),
            (.gradient, 2),
            (.glass, 3),
            (.none, 4),
            (.sampled, 5),
        ])
        func backgroundKindRawValues(kind: ThawBarBackgroundKind, raw: Int) {
            #expect(kind.rawValue == raw)
        }

        @Test("Corner style raw values stay stable for persistence", arguments: [
            (ThawBarCornerStyle.rounded, 0),
            (.square, 1),
        ])
        func cornerStyleRawValues(style: ThawBarCornerStyle, raw: Int) {
            #expect(style.rawValue == raw)
        }

        @Test("Unknown background kind raw values fail to decode")
        func unknownBackgroundKindFails() throws {
            let data = Data("99".utf8)
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(ThawBarBackgroundKind.self, from: data)
            }
        }

        @Test("Unknown corner style raw values fail to decode")
        func unknownCornerStyleFails() throws {
            let data = Data("99".utf8)
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(ThawBarCornerStyle.self, from: data)
            }
        }
    }

    @Suite("Partial configuration")
    struct PartialTests {
        @Test("Defaults use match-menu-bar sample, no tint, rounded corners, and omit-top for square")
        func defaults() {
            let config = ThawBarAppearancePartialConfiguration.defaultConfiguration

            #expect(config.backgroundKind == .adaptive)
            #expect(config.backgroundGlassStyle == .clear)
            #expect(config.backgroundOpacity == 1)
            #expect(config.adaptiveBrightness == 0)
            #expect(config.adaptiveGlassAmount == 0)
            #expect(config.tintKind == .noTint)
            #expect(config.cornerStyle == .rounded)
            #expect(!config.hasBorder)
            #expect(config.omitTopBorderWhenSquare)
            #expect(config.hasShadow)
            #expect(!config.appliesLiquidGlass)
        }

        @Test("Migration clears tint and carries Thaw Bar border from the menu bar partial")
        func migratingFromMenuBarPartial() {
            var menuBar = MenuBarAppearancePartialConfiguration.defaultConfiguration
            menuBar.borderOnThawBar = true
            menuBar.borderWidth = 2
            menuBar.tintKind = .solid

            let thawBar = ThawBarAppearancePartialConfiguration.migrating(from: menuBar)

            #expect(thawBar.hasBorder)
            #expect(thawBar.borderWidth == 2)
            #expect(thawBar.tintKind == .noTint)
            #expect(thawBar.backgroundKind == .adaptive)
            #expect(thawBar.backgroundGlassStyle == .clear)
            #expect(thawBar.omitTopBorderWhenSquare)
        }

        @Test("The default partial survives a round trip")
        func encodeDecode() throws {
            let original = ThawBarAppearancePartialConfiguration.defaultConfiguration
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ThawBarAppearancePartialConfiguration.self, from: data)

            #expect(decoded == original)
        }

        @Test("An empty payload decodes to the defaults")
        func decodeEmpty() throws {
            let decoded = try JSONDecoder().decode(
                ThawBarAppearancePartialConfiguration.self,
                from: Data("{}".utf8)
            )
            #expect(decoded == .defaultConfiguration)
        }

        @Test("shouldOmitTopBorder is true only for square corners with the preference on")
        func shouldOmitTopBorder() {
            var config = ThawBarAppearancePartialConfiguration.defaultConfiguration
            config.hasBorder = true
            config.cornerStyle = .square
            config.omitTopBorderWhenSquare = true
            #expect(config.shouldOmitTopBorder)

            config.omitTopBorderWhenSquare = false
            #expect(!config.shouldOmitTopBorder)

            config.omitTopBorderWhenSquare = true
            config.cornerStyle = .rounded
            #expect(!config.shouldOmitTopBorder)

            config.cornerStyle = .square
            config.hasBorder = false
            #expect(!config.shouldOmitTopBorder)
        }

        @Test("Corner radius matches pill vs square sizing")
        func cornerRadius() {
            var config = ThawBarAppearancePartialConfiguration.defaultConfiguration
            config.cornerStyle = .rounded
            #expect(config.cornerRadius(contentHeight: 40) == 20)

            config.cornerStyle = .square
            #expect(config.cornerRadius(contentHeight: 40) == 10)
        }

        @Test("Resolved fill color follows the background kind")
        func resolvedFillColor() {
            var config = ThawBarAppearancePartialConfiguration.defaultConfiguration
            let sampled = CGColor(gray: 0.8, alpha: 1)

            config.backgroundKind = .adaptive
            #expect(config.resolvedFillColor(sampled: sampled) === sampled)

            config.adaptiveBrightness = 0.5
            let brightened = config.resolvedFillColor(sampled: sampled)
            #expect(brightened != nil)
            #expect(brightened !== sampled)

            config.backgroundKind = .sampled
            #expect(config.resolvedFillColor(sampled: sampled) === sampled)

            config.backgroundKind = .solid
            config.backgroundColor = CGColor(gray: 0.2, alpha: 1)
            #expect(config.resolvedFillColor(sampled: sampled) === config.backgroundColor)

            config.backgroundKind = .none
            #expect(config.resolvedFillColor(sampled: sampled) === sampled)
        }

        @Test("Translucent fills composite over the sample before contrast")
        func translucentFillCompositesForContrast() throws {
            var config = ThawBarAppearancePartialConfiguration.defaultConfiguration
            config.backgroundKind = .solid
            config.backgroundColor = CGColor(gray: 1, alpha: 1)
            config.backgroundOpacity = 0.25
            let darkSample = CGColor(gray: 0.1, alpha: 1)

            let resolved = try #require(config.resolvedFillColor(sampled: darkSample))
            let components = try #require(resolved.components)
            // 0.25 white over 0.1 gray ≈ 0.325 — well below a light fill.
            #expect(components[0] < 0.5)
            #expect(components[0] > 0.2)
        }

        @Test("Glass kind always uses liquid glass; Match Menu Bar follows the glass slider")
        func appliesLiquidGlass() {
            #expect(ThawBarBackgroundKind.glass.usesLiquidGlass)
            #expect(!ThawBarBackgroundKind.adaptive.usesLiquidGlass)

            var config = ThawBarAppearancePartialConfiguration.defaultConfiguration
            config.backgroundKind = .adaptive
            #expect(!config.appliesLiquidGlass)

            config.adaptiveGlassAmount = 0.25
            #expect(config.appliesLiquidGlass)

            config.backgroundKind = .glass
            #expect(config.appliesLiquidGlass)
        }

        @Test("Brightness adjustment mixes toward white or black")
        func adjustingBrightness() {
            let mid = CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
            let lighter = ThawBarAppearancePartialConfiguration.adjustingBrightness(of: mid, by: 1)
            let darker = ThawBarAppearancePartialConfiguration.adjustingBrightness(of: mid, by: -1)
            #expect(lighter?.components?[0] == 1)
            #expect(darker?.components?[0] == 0)
            #expect(ThawBarAppearancePartialConfiguration.adjustingBrightness(of: mid, by: 0) === mid)
        }

        @Test("prefersDarkForeground uses the resolved fill brightness")
        func prefersDarkForeground() {
            var config = ThawBarAppearancePartialConfiguration.defaultConfiguration
            config.backgroundKind = .solid
            config.backgroundColor = CGColor(gray: 0.95, alpha: 1)

            #expect(
                config.prefersDarkForeground(
                    sampledColor: nil,
                    sampledBrightness: nil,
                    screenHasNotch: false
                )
            )

            config.backgroundColor = CGColor(gray: 0.1, alpha: 1)
            #expect(
                !config.prefersDarkForeground(
                    sampledColor: nil,
                    sampledBrightness: nil,
                    screenHasNotch: false
                )
            )
        }
    }

    @Suite("V2 integration")
    struct V2IntegrationTests {
        @Test("V2 defaults include Thaw Bar defaults")
        func v2Defaults() {
            let config = MenuBarAppearanceConfigurationV2.defaultConfiguration
            #expect(config.thawBarStaticConfiguration == .defaultConfiguration)
            #expect(config.thawBarLightModeConfiguration == .defaultConfiguration)
            #expect(config.thawBarDarkModeConfiguration == .defaultConfiguration)
        }

        @Test("A legacy V2 payload without thawBar keys migrates borders and clears tint")
        func legacyV2Migration() throws {
            var menuBar = MenuBarAppearancePartialConfiguration.defaultConfiguration
            menuBar.borderOnThawBar = true
            menuBar.borderWidth = 3
            menuBar.tintKind = .solid

            let legacy = MenuBarAppearanceConfigurationV2(
                lightModeConfiguration: menuBar,
                darkModeConfiguration: menuBar,
                staticConfiguration: menuBar,
                thawBarLightModeConfiguration: .defaultConfiguration,
                thawBarDarkModeConfiguration: .defaultConfiguration,
                thawBarStaticConfiguration: .defaultConfiguration,
                shapeKind: .noShape,
                fullShapeInfo: .defaultValue,
                splitShapeInfo: .defaultValue,
                notchShapeInfo: .defaultValue,
                isInset: true,
                leftMargin: 0,
                rightMargin: 0,
                notchMargin: 0,
                isDynamic: false
            )

            // Strip thawBar keys to simulate a pre-feature payload.
            let encoded = try JSONEncoder().encode(legacy)
            var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            object.removeValue(forKey: "thawBarLightModeConfiguration")
            object.removeValue(forKey: "thawBarDarkModeConfiguration")
            object.removeValue(forKey: "thawBarStaticConfiguration")
            let stripped = try JSONSerialization.data(withJSONObject: object)

            let decoded = try JSONDecoder().decode(MenuBarAppearanceConfigurationV2.self, from: stripped)

            #expect(decoded.thawBarStaticConfiguration.hasBorder)
            #expect(decoded.thawBarStaticConfiguration.borderWidth == 3)
            #expect(decoded.thawBarStaticConfiguration.tintKind == .noTint)
            #expect(decoded.thawBarStaticConfiguration.backgroundKind == .adaptive)
        }

        @Test("Thaw Bar fields survive a V2 round trip")
        func v2RoundTrip() throws {
            var config = MenuBarAppearanceConfigurationV2.defaultConfiguration
            config.thawBarStaticConfiguration.backgroundKind = .solid
            config.thawBarStaticConfiguration.backgroundColor = CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
            config.thawBarStaticConfiguration.cornerStyle = .square
            config.thawBarStaticConfiguration.hasBorder = true
            config.thawBarStaticConfiguration.omitTopBorderWhenSquare = false

            let decoded = try JSONDecoder().decode(
                MenuBarAppearanceConfigurationV2.self,
                from: try JSONEncoder().encode(config)
            )

            #expect(decoded.thawBarStaticConfiguration.backgroundKind == .solid)
            #expect(decoded.thawBarStaticConfiguration.cornerStyle == .square)
            #expect(decoded.thawBarStaticConfiguration.hasBorder)
            #expect(!decoded.thawBarStaticConfiguration.omitTopBorderWhenSquare)
        }
    }
}

@Suite("Thaw Bar border shape")
struct ThawBarBorderShapeTests {
    @Test("A closed border path is a continuous rounded rectangle")
    func closedPath() {
        let shape = ThawBarBorderShape(cornerRadius: 8, omitTopEdge: false)
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(!path.isEmpty)
        // Closed shapes report a non-zero bounding box matching the rect.
        #expect(path.boundingRect.width > 0)
        #expect(path.boundingRect.height > 0)
    }

    @Test("An open-top path still spans the full width and height")
    func openTopPath() {
        let shape = ThawBarBorderShape(cornerRadius: 8, omitTopEdge: true, inset: 0.5)
        let rect = CGRect(x: 0, y: 0, width: 120, height: 36)
        let path = shape.path(in: rect)
        #expect(!path.isEmpty)
        #expect(path.boundingRect.maxY <= rect.maxY)
        #expect(path.boundingRect.minX >= rect.minX)
    }
}
