//
//  ThawBarForegroundFillTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

@MainActor
@Suite("Thaw Bar foreground over gradient, palette and dimmed fills")
struct ThawBarForegroundFillTests {
    private static let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    private static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    /// Light enough for black ink alone, dark enough for white ink once half dimmed.
    private static let lightGray = CGColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1)

    private func gradient(_ color: CGColor) -> ThawGradient {
        ThawGradient(stops: [.stop(color, location: 0), .stop(color, location: 1)])
    }

    private func ink(
        sample: CGColor,
        adaptive: CGColor? = nil,
        palette: WallpaperPalette? = nil,
        configure: (inout ThawBarAppearance) -> Void
    ) -> Color {
        var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        configuration.thawBarAppearance.overridesMenuBar = true
        configuration.thawBarAppearance.backgroundKind = .none
        configuration.thawBarAppearance.tintKind = .noTint
        configuration.thawBarAppearance.backgroundOpacity = 1
        configuration.thawBarAppearance.tintOpacity = 1
        configure(&configuration.thawBarAppearance)
        return ThawBarAppearanceForeground.resolve(
            appearance: configuration.resolvedThawBarAppearance,
            sampledInfo: MenuBarAverageColorInfo(color: sample, source: .menuBarWindow),
            adaptiveInfo: adaptive.map { MenuBarAverageColorInfo(color: $0, source: .menuBarWindow) },
            palette: palette,
            screen: nil
        )
    }

    @Test("An opaque gradient background decides the ink, whatever the sample beneath it", arguments: [false, true])
    func gradientBackground(isLight: Bool) {
        let fill = isLight ? Self.white : Self.black
        let sample = isLight ? Self.black : Self.white
        let result = ink(sample: sample) {
            $0.backgroundKind = .gradient
            $0.backgroundGradient = gradient(fill)
        }
        #expect(result == (isLight ? .black : .white))
    }

    @Test("An opaque gradient tint decides the ink, whatever the sample beneath it", arguments: [false, true])
    func gradientTint(isLight: Bool) {
        let fill = isLight ? Self.white : Self.black
        let sample = isLight ? Self.black : Self.white
        let result = ink(sample: sample) {
            $0.tintKind = .gradient
            $0.tintGradient = gradient(fill)
        }
        #expect(result == (isLight ? .black : .white))
    }

    @Test("A gradient with no stops leaves the sample's ink alone")
    func emptyGradientsAreIgnored() {
        let result = ink(sample: Self.white) {
            $0.backgroundKind = .gradient
            $0.backgroundGradient = ThawGradient()
            $0.tintKind = .gradient
            $0.tintGradient = ThawGradient()
        }
        #expect(result == .black)
    }

    @Test("The adaptive gradient tint follows the wallpaper palette's average")
    func adaptiveGradientUsesThePalette() {
        let light = WallpaperPalette(swatches: [
            .init(red: 1, green: 1, blue: 1, weight: 0.6),
            .init(red: 0.9, green: 0.9, blue: 0.9, weight: 0.4),
        ])
        let dark = WallpaperPalette(swatches: [
            .init(red: 0, green: 0, blue: 0, weight: 0.6),
            .init(red: 0.1, green: 0.1, blue: 0.1, weight: 0.4),
        ])
        let overLight = ink(sample: Self.black, adaptive: Self.black, palette: light) { $0.tintKind = .adaptiveGradient }
        let overDark = ink(sample: Self.white, adaptive: Self.white, palette: dark) { $0.tintKind = .adaptiveGradient }
        #expect(overLight == .black)
        #expect(overDark == .white)
    }

    @Test("Without a palette the adaptive gradient tint falls back to the adaptive sample")
    func adaptiveGradientFallsBackToTheAdaptiveSample() {
        let empty = WallpaperPalette(swatches: [])
        #expect(ink(sample: Self.white, adaptive: Self.black, palette: nil) { $0.tintKind = .adaptiveGradient } == .white)
        #expect(ink(sample: Self.white, adaptive: Self.black, palette: empty) { $0.tintKind = .adaptiveGradient } == .white)
        #expect(ink(sample: Self.black, adaptive: Self.white, palette: nil) { $0.tintKind = .adaptiveGradient } == .black)
    }

    @Test("Dim glass darkens a light bar enough to flip the ink, plain glass does not", arguments: [false, true])
    func dimGlassDarkens(asTint: Bool) {
        func glass(_ style: MenuBarGlassStyle) -> Color {
            ink(sample: Self.lightGray) {
                if asTint {
                    $0.tintKind = .glass
                    $0.tintGlassStyle = style
                } else {
                    $0.backgroundKind = .glass
                    $0.backgroundGlassStyle = style
                }
            }
        }
        #expect(glass(.regular) == .black)
        #expect(glass(.dim) == .white)
    }
}
