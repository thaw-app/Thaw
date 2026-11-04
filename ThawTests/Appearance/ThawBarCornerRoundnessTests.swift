//
//  ThawBarCornerRoundnessTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

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
