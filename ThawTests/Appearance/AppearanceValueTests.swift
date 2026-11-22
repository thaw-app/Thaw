//
//  AppearanceValueTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Appearance values, labels and decoding")
struct AppearanceValueTests {
    @Test("Each border style has its own label")
    func borderStyleLabels() {
        let labels = Set(MenuBarBorderStyle.allCases.map { String(localized: $0.localized) })
        #expect(labels.count == MenuBarBorderStyle.allCases.count)
    }

    @Test("A swatch converts to an opaque color with its own components")
    func swatchColor() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let swatch = WallpaperPalette.Swatch(red: 0.25, green: 0.5, blue: 0.75, weight: 1)
        let color = try #require(swatch.cgColor(in: space))
        #expect(color.components == [0.25, 0.5, 0.75, 1])
        #expect(color.colorSpace == space)
    }

    @Test("The resolved Thaw Bar reports the fill's background shadow")
    func resolvedBackgroundShadow() {
        var fill = MenuBarAppearancePartialConfiguration.defaultConfiguration
        for hasShadow in [false, true] {
            fill.backgroundHasShadow = hasShadow
            let resolved = ResolvedThawBarAppearance(hasRoundedShape: false, fillConfiguration: fill)
            #expect(resolved.backgroundHasShadow == hasShadow)
        }
    }

    @Test("A dynamic appearance picks the configuration for the current system appearance")
    func dynamicConfigurationFollowsTheSystem() {
        var config = MenuBarAppearanceConfigurationV2.defaultConfiguration
        config.lightModeConfiguration.tintOpacity = 0.1
        config.darkModeConfiguration.tintOpacity = 0.9
        config.staticConfiguration.tintOpacity = 0.5
        config.isDynamic = false
        #expect(config.current.tintOpacity == 0.5)
        config.isDynamic = true
        let expected = SystemAppearance.current == .dark ? 0.9 : 0.1
        #expect(config.current.tintOpacity == expected)
    }

    @Test("A string navigation identifier is labelled and identified by its raw value")
    func navigationIdentifierDefaults() {
        #expect(String(localized: ProbeDestination.alpha.localized) == "Alpha")
        #expect(String(localized: ProbeDestination.beta.localized) == "Beta")
        #expect(ProbeDestination.alpha.id == ProbeDestination.alpha.hashValue)
        #expect(ProbeDestination.alpha.id != ProbeDestination.beta.id)
    }
}

/// Takes the protocol's defaults for id and localized, which every shipped conformer overrides or shadows.
private enum ProbeDestination: String, @MainActor NavigationIdentifier {
    case alpha = "Alpha"
    case beta = "Beta"

    var iconResource: IconResource {
        .systemSymbol("circle")
    }
}

struct MenuBarBackgroundSettingTests {
    @Test
    func `the background is on only when SkyLight's preference says so`() {
        #expect(MenuBarBackgroundSetting.isOn { $0 == MenuBarBackgroundSetting.key ? NSNumber(value: true) : nil })
        #expect(!MenuBarBackgroundSetting.isOn { _ in NSNumber(value: false) })
    }

    @Test
    func `an unset or unreadable preference counts as off`() {
        #expect(!MenuBarBackgroundSetting.isOn { _ in nil })
        #expect(!MenuBarBackgroundSetting.isOn { _ in "yes" })
    }

    @Test
    func `the live read takes the switch from the global domain`() {
        let global = CFPreferencesCopyAppValue(MenuBarBackgroundSetting.key as CFString, kCFPreferencesAnyApplication)
        #expect(MenuBarBackgroundSetting.isOn() == ((global as? NSNumber)?.boolValue ?? false))
    }
}
