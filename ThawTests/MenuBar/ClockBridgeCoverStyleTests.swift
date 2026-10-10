//
//  ClockBridgeCoverStyleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Clock bridge cover style")
struct ClockBridgeCoverStyleTests {
    private let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)

    private func configuration(
        background: MenuBarBackgroundKind = .none,
        tint: MenuBarTintKind = .noTint,
        glass: MenuBarGlassStyle = .regular,
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
        config.tintGlassIsColored = colored
        return config
    }

    @Test("No look means bare wallpaper")
    func bareWallpaper() {
        let style = ClockBridgeCoverStyle.style(for: configuration(), shapeKind: .noShape, adaptiveColor: nil)
        #expect(style.washes.isEmpty)
        #expect(!style.blursWallpaper)
    }

    @Test("The background fill always applies")
    func backgroundApplies() {
        let style = ClockBridgeCoverStyle.style(for: configuration(background: .solid), shapeKind: .split, adaptiveColor: nil)
        #expect(style.washes == [.init(color: red, opacity: 0.5)])
    }

    @Test("The shape fill applies with no shape or a Full shape, not beside a Split or Notch shape")
    func shapeFillWhereItCoversTheBand() {
        let config = configuration(tint: .solid)
        #expect(ClockBridgeCoverStyle.style(for: config, shapeKind: .noShape, adaptiveColor: nil).washes.count == 1)
        #expect(ClockBridgeCoverStyle.style(for: config, shapeKind: .full, adaptiveColor: nil).washes.count == 1)
        #expect(ClockBridgeCoverStyle.style(for: config, shapeKind: .split, adaptiveColor: nil).washes.isEmpty)
        #expect(ClockBridgeCoverStyle.style(for: config, shapeKind: .notch, adaptiveColor: nil).washes.isEmpty)
    }

    @Test("Colored liquid glass frosts the wallpaper and adds its tint at the glass strength")
    func coloredLiquidGlass() {
        let style = ClockBridgeCoverStyle.style(
            for: configuration(tint: .glass, glass: .liquid, colored: true),
            shapeKind: .full,
            adaptiveColor: nil
        )
        #expect(style.blursWallpaper)
        #expect(style.washes == [.init(color: red, opacity: 0.4 * MenuBarGlassStyle.liquid.effectOpacity)])
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

    @Test("Glass that follows the system is Regular while Tinted and Clear while Clear")
    func systemGlass() {
        var config = MenuBarAppearancePartialConfiguration.defaultConfiguration
        config.tintGlassStyle = .liquid
        config.backgroundGlassStyle = .liquid
        config.tintGlassFollowsSystem = true
        #expect(config.withSystemGlass(tinted: true).tintGlassStyle == .regular)
        #expect(config.withSystemGlass(tinted: false).tintGlassStyle == .clear)
        #expect(config.withSystemGlass(tinted: true).backgroundGlassStyle == .liquid)
    }

    @Test("A saved look without the new keys decodes with accent off")
    func olderSavedLookDecodes() throws {
        let data = try JSONEncoder().encode(MenuBarAppearancePartialConfiguration.defaultConfiguration)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "backgroundUsesAccentColor")
        object.removeValue(forKey: "tintUsesAccentColor")
        object.removeValue(forKey: "backgroundGlassFollowsSystem")
        object.removeValue(forKey: "tintGlassFollowsSystem")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MenuBarAppearancePartialConfiguration.self, from: stripped)
        #expect(!decoded.backgroundUsesAccentColor && !decoded.tintUsesAccentColor)
        #expect(!decoded.backgroundGlassFollowsSystem && !decoded.tintGlassFollowsSystem)
    }
}
