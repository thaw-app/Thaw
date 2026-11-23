//
//  ThawBarAppearanceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@MainActor
struct ThawBarAppearanceTests {
    @Test func inheritsMenuBarFillWithoutReplacingOpacity() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.shapeKind = .full
        configuration.staticConfiguration.tintOpacity = 0.75
        configuration.staticConfiguration.tintKind = .adaptiveGradient
        configuration.staticConfiguration.backgroundKind = .glass
        configuration.staticConfiguration.backgroundOpacity = 0.6
        configuration.staticConfiguration.hasShadow = true
        configuration.staticConfiguration.backgroundHasBorder = true
        configuration.staticConfiguration.tintGlassIsColored = true

        #expect(configuration.resolvedThawBarAppearance.fillConfiguration == configuration.staticConfiguration)
    }

    @Test func inheritsNoBorderWhenTheMenuBarHasNoShape() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.isDynamic = false
        configuration.staticConfiguration.hasBorder = true

        configuration.shapeKind = .noShape
        #expect(!configuration.resolvedThawBarAppearance.hasBorder)

        configuration.shapeKind = .full
        #expect(configuration.resolvedThawBarAppearance.hasBorder)
    }

    @Test func seededOverridePreservesAllInheritedFields() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.staticConfiguration.tintKind = .glass
        configuration.staticConfiguration.tintOpacity = 0.85
        configuration.staticConfiguration.backgroundKind = .adaptive
        configuration.staticConfiguration.backgroundHasShadow = true
        let inherited = configuration.resolvedThawBarAppearance

        configuration.thawBarAppearance = ThawBarAppearance(seededFrom: inherited)
        configuration.staticConfiguration.tintOpacity = 0.1

        #expect(configuration.resolvedThawBarAppearance == inherited)
    }

    @Test func olderOverrideKeepsItsValuesAndDefaultsNewFields() throws {
        let data = Data(#"{"overridesMenuBar":true,"hasRoundedShape":true,"tintOpacity":0.65,"hasBorder":true,"borderWidth":3}"#.utf8)
        let decoded = try JSONDecoder().decode(ThawBarAppearance.self, from: data)

        #expect(decoded.overridesMenuBar)
        #expect(decoded.hasRoundedShape)
        #expect(decoded.tintOpacity == 0.65)
        #expect(decoded.hasBorder)
        #expect(decoded.borderWidth == 3)
        // Compared with the shared default, so changing a default doesn't fail this test.
        let fallback = MenuBarAppearancePartialConfiguration.defaultConfiguration
        #expect(decoded.backgroundKind == fallback.backgroundKind)
        #expect(decoded.backgroundHasBorder == fallback.backgroundHasBorder)
        #expect(decoded.hasShadow == fallback.hasShadow)
    }

    @Test func extendedOverrideRoundTrips() throws {
        var appearance = ThawBarAppearance.defaultConfiguration
        appearance.overridesMenuBar = true
        appearance.backgroundKind = .glass
        appearance.backgroundGlassIsColored = true
        appearance.backgroundOpacity = 0.7
        appearance.backgroundHasBorder = true
        appearance.backgroundBorderWidth = 2
        appearance.hasShadow = true
        appearance.tintKind = .adaptiveGradient
        appearance.tintGlassIsColored = true
        let encoded = try JSONEncoder().encode(appearance)

        #expect(try JSONDecoder().decode(ThawBarAppearance.self, from: encoded) == appearance)
    }

    @Test("The saved look holds exactly the keys earlier releases wrote, with no border style")
    func storedKeysAreUnchanged() throws {
        var appearance = ThawBarAppearance.defaultConfiguration
        appearance.overridesMenuBar = true
        appearance.cornerRoundness = 0.5
        let encoded = try JSONEncoder().encode(appearance)
        let keys = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any]).keys

        #expect(Set(keys) == [
            "overridesMenuBar", "cornerRoundness", "hasRoundedShape",
            "hasShadow", "hasBorder", "borderColor", "borderWidth",
            "tintKind", "tintColor", "tintGradient", "tintOpacity",
            "backgroundKind", "backgroundColor", "backgroundGradient", "backgroundOpacity",
            "backgroundHasShadow", "backgroundHasBorder", "backgroundBorderColor", "backgroundBorderWidth",
            "backgroundGlassStyle", "tintGlassStyle", "backgroundGlassIsColored", "tintGlassIsColored",
            "backgroundUsesAccentColor", "tintUsesAccentColor", "backgroundGlassIsTinted", "tintGlassIsTinted",
        ])
    }

    @Test("The Thaw Bar keeps a solid border however the style arrives")
    func borderStyleStaysSolid() throws {
        var dashed = MenuBarAppearancePartialConfiguration.defaultConfiguration
        dashed.borderStyle = .dashed

        var appearance = ThawBarAppearance(overridesMenuBar: true, cornerRoundness: 0, fillConfiguration: dashed)
        #expect(appearance.fillConfiguration.borderStyle == .solid)

        appearance.fillConfiguration = dashed
        #expect(appearance.fillConfiguration.borderStyle == .solid)

        appearance.borderStyle = .dashed
        #expect(appearance.fillConfiguration.borderStyle == .solid)

        let seeded = ThawBarAppearance(seededFrom: ResolvedThawBarAppearance(cornerRoundness: 0, fillConfiguration: dashed))
        #expect(seeded.fillConfiguration.borderStyle == .solid)

        let stored = Data(#"{"overridesMenuBar":true,"borderStyle":1}"#.utf8)
        #expect(try JSONDecoder().decode(ThawBarAppearance.self, from: stored).fillConfiguration.borderStyle == .solid)
    }

    @Test("A fill value set on the look reads back through the fill configuration")
    func memberAccessReachesTheFill() {
        var appearance = ThawBarAppearance.defaultConfiguration
        appearance.tintOpacity = 0.4
        #expect(appearance.fillConfiguration.tintOpacity == 0.4)
        #expect(ResolvedThawBarAppearance(cornerRoundness: 0, fillConfiguration: appearance.fillConfiguration).tintOpacity == 0.4)
    }
}

/// The Thaw Bar's corners follow a Square-to-Round slider, like the menu bar's shape.
@MainActor
@Suite("Thaw Bar corner roundness")
struct ThawBarCornerRoundnessTests {
    // MARK: Saved looks

    @Test("A look saved with the old toggle opens round or square", arguments: [(true, 1.0), (false, 0.0)])
    func oldToggleBecomesRoundness(rounded: Bool, roundness: Double) throws {
        let data = Data(#"{"overridesMenuBar":true,"hasRoundedShape":\#(rounded)}"#.utf8)
        #expect(try JSONDecoder().decode(ThawBarAppearance.self, from: data).cornerRoundness == roundness)
    }

    @Test("A look saved before the setting opens square")
    func missingRoundnessIsSquare() throws {
        let data = Data(#"{"overridesMenuBar":true}"#.utf8)
        #expect(try JSONDecoder().decode(ThawBarAppearance.self, from: data).cornerRoundness == 0)
    }

    @Test("Roundness survives a save, and older versions still read the toggle", arguments: [0.4, 0.0])
    func roundnessRoundTrips(roundness: Double) throws {
        var appearance = ThawBarAppearance.defaultConfiguration
        appearance.cornerRoundness = roundness
        let data = try JSONEncoder().encode(appearance)

        #expect(try JSONDecoder().decode(ThawBarAppearance.self, from: data).cornerRoundness == roundness)
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(fields["hasRoundedShape"] as? Bool == (roundness > 0))
    }

    @Test("A damaged saved roundness is kept between square and round")
    func damagedRoundnessIsClamped() throws {
        let data = Data(#"{"overridesMenuBar":true,"cornerRoundness":7}"#.utf8)
        #expect(try JSONDecoder().decode(ThawBarAppearance.self, from: data).cornerRoundness == 1)
    }

    // MARK: Where the roundness comes from

    @Test("Following the menu bar, the Thaw Bar takes the menu bar's Corners slider")
    func followsMenuBarSlider() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.shapeKind = .full
        configuration.fullShapeInfo = MenuBarShapeRoundness.info(for: 0.4)
        #expect(configuration.resolvedThawBarAppearance.cornerRoundness == 0.4)

        configuration.shapeKind = .noShape
        #expect(configuration.resolvedThawBarAppearance.cornerRoundness == 0)
    }

    @Test("With its own look, the Thaw Bar uses its own roundness")
    func ownLookUsesOwnRoundness() {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.shapeKind = .full
        configuration.fullShapeInfo = MenuBarShapeRoundness.info(for: 1)
        configuration.thawBarAppearance.overridesMenuBar = true
        configuration.thawBarAppearance.cornerRoundness = 0.25
        #expect(configuration.resolvedThawBarAppearance.cornerRoundness == 0.25)
    }

    // MARK: The drawn shape

    @Test("The ends of the slider draw exactly the old square and round shapes")
    func endsMatchTheOldShapes() {
        let square = ThawBarBorderShape.thawBarClip(height: 24, roundness: 0)
        #expect(square.cornerRadius == 6)
        #expect(square.cornerStyle == .continuous)
        let round = ThawBarBorderShape.thawBarClip(height: 24, roundness: 1)
        #expect(round.cornerRadius == 12)
        #expect(round.cornerStyle == .circular)
    }

    @Test("A value between them draws corners between them")
    func middleIsBetween() {
        let clip = ThawBarBorderShape.thawBarClip(height: 24, roundness: 0.5)
        #expect(clip.cornerRadius == 9)
    }
}
