//
//  RevealCoverStyleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw
import ThawUI

@MainActor
@Suite("Clock bridge cover style")
struct RevealCoverStyleTests {
    private let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)

    private func configuration(
        background: MenuBarBackgroundKind = .none,
        tint: MenuBarTintKind = .noTint,
        glass: MenuBarGlassStyle = .regular,
        tinted: Bool = false,
        colored: Bool = false
    ) -> MenuBarAppearancePartialConfiguration {
        var config = MenuBarAppearancePartialConfiguration.defaultConfiguration
        config.backgroundKind = background
        config.backgroundColor = red
        config.backgroundOpacity = 0.5
        config.tintKind = tint
        config.tintColor = red
        config.tintOpacity = 0.4
        config.tintGlassStyle = glass
        config.tintGlassIsTinted = tinted
        config.tintGlassIsColored = colored
        return config
    }

    @Test("No look means bare wallpaper")
    func bareWallpaper() {
        let style = RevealCoverStyle.style(for: configuration(), shapeKind: .noShape, adaptiveColor: nil)
        #expect(style.washes.isEmpty)
        #expect(!style.blursWallpaper)
    }

    @Test("The background fill always applies")
    func backgroundApplies() {
        let style = RevealCoverStyle.style(for: configuration(background: .solid), shapeKind: .split, adaptiveColor: nil)
        #expect(style.washes == [.init(color: red, opacity: 0.5)])
    }

    @Test("The shape fill applies with a Full shape, not with no shape or beside a Split or Notch shape")
    func shapeFillWhereItCoversTheBand() {
        let config = configuration(tint: .solid)
        #expect(RevealCoverStyle.style(for: config, shapeKind: .noShape, adaptiveColor: nil).washes.isEmpty)
        #expect(RevealCoverStyle.style(for: config, shapeKind: .full, adaptiveColor: nil).washes.count == 1)
        #expect(RevealCoverStyle.style(for: config, shapeKind: .split, adaptiveColor: nil).washes.isEmpty)
        #expect(RevealCoverStyle.style(for: config, shapeKind: .notch, adaptiveColor: nil).washes.isEmpty)
    }

    @Test("With no shape only a glass fill applies, as only that one is on the bar")
    func noShapeKeepsGlassFill() {
        let glass = configuration(tint: .glass)
        #expect(RevealCoverStyle.style(for: glass, shapeKind: .noShape, adaptiveColor: nil).blursWallpaper)
        for tint in [MenuBarTintKind.solid, .gradient] {
            let style = RevealCoverStyle.style(for: configuration(tint: tint), shapeKind: .noShape, adaptiveColor: nil)
            #expect(style.washes.isEmpty)
        }
        let adaptive = RevealCoverStyle.style(for: configuration(tint: .adaptive), shapeKind: .noShape, adaptiveColor: red)
        #expect(adaptive.washes.isEmpty)
    }

    @Test("Tinted, colored glass frosts the wallpaper and adds its color at the glass strength")
    func coloredTintedGlass() {
        let config = configuration(tint: .glass, tinted: true, colored: true)
        let style = RevealCoverStyle.style(
            for: config,
            shapeKind: .full,
            adaptiveColor: nil
        )
        #expect(style.blursWallpaper)
        #expect(style.washes == [.init(color: red, opacity: 0.4 * config.tintGlassFinish.effectOpacity)])
    }

    @Test("A gradient fill washes its average color, and an empty gradient washes nothing")
    func gradientFill() throws {
        var config = configuration(background: .gradient)
        config.backgroundGradient = ThawGradient(stops: [.white(location: 0), .white(location: 1)])
        let style = RevealCoverStyle.style(for: config, shapeKind: .split, adaptiveColor: nil)
        let wash = try #require(style.washes.first)
        #expect(style.washes.count == 1)
        #expect(wash.opacity == 0.5)
        #expect(abs((wash.color.components?.first ?? 0) - 1) < 0.01, "white averages to white")
        config.backgroundGradient = ThawGradient()
        #expect(RevealCoverStyle.style(for: config, shapeKind: .split, adaptiveColor: nil).washes.isEmpty)
    }

    @Test("An adaptive fill washes the sampled color, and nothing until one is sampled")
    func adaptiveFill() {
        let sampled = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        let config = configuration(tint: .adaptiveGradient)
        #expect(RevealCoverStyle.style(for: config, shapeKind: .full, adaptiveColor: sampled).washes == [.init(color: sampled, opacity: 0.4)])
        #expect(RevealCoverStyle.style(for: config, shapeKind: .full, adaptiveColor: nil).washes.isEmpty)
    }

    @Test("Dynamic glass adds its dark fade, and uncolored glass only frosts")
    func dynamicGlass() {
        let dynamic = RevealCoverStyle.style(for: configuration(tint: .glass, glass: .dynamic), shapeKind: .noShape, adaptiveColor: nil)
        #expect(dynamic.blursWallpaper)
        #expect(dynamic.washes == [.init(color: CGColor(gray: 0, alpha: 1), opacity: RevealCoverStyle.darkFadeOpacity)])
        let plain = RevealCoverStyle.style(for: configuration(tint: .glass, glass: .regular, colored: true), shapeKind: .noShape, adaptiveColor: nil)
        #expect(plain.blursWallpaper)
        #expect(plain.washes.isEmpty, "regular glass takes no tint")
    }
}

@Suite("Accent color follow")
struct AccentColorFollowTests {
    private let accent = CGColor(red: 0, green: 0.5, blue: 1, alpha: 1)
    private let stored = CGColor(red: 1, green: 0, blue: 0, alpha: 1)

    @Test("Only surfaces that follow the accent take it")
    func onlyFollowersChange() {
        var config = MenuBarAppearancePartialConfiguration.defaultConfiguration
        config.backgroundColor = stored
        config.tintColor = stored
        config.tintUsesAccentColor = true
        let synced = config.withAccentColor(accent)
        #expect(synced.tintColor == accent)
        #expect(synced.backgroundColor == stored)
    }

    @Test("The Thaw Bar's own look follows the accent too, and keeps the flag")
    func thawBarFollows() {
        var config = MenuBarAppearanceConfigurationV2.defaultConfiguration
        var fill = config.thawBarAppearance.fillConfiguration
        fill.backgroundUsesAccentColor = true
        config.thawBarAppearance.fillConfiguration = fill
        let synced = config.withAccentColor(accent)
        #expect(synced.thawBarAppearance.fillConfiguration.backgroundColor == accent)
        #expect(synced.thawBarAppearance.backgroundUsesAccentColor)
    }

    @Test("A saved look without the new keys decodes with accent and Tint off")
    func olderSavedLookDecodes() throws {
        let data = try JSONEncoder().encode(MenuBarAppearancePartialConfiguration.defaultConfiguration)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "backgroundUsesAccentColor")
        object.removeValue(forKey: "tintUsesAccentColor")
        object.removeValue(forKey: "backgroundGlassIsTinted")
        object.removeValue(forKey: "tintGlassIsTinted")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MenuBarAppearancePartialConfiguration.self, from: stripped)
        #expect(!decoded.backgroundUsesAccentColor && !decoded.tintUsesAccentColor)
        #expect(!decoded.backgroundGlassIsTinted && !decoded.tintGlassIsTinted)
    }
}
