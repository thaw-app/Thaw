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
    @Test("Each shape kind is identified by its stored raw value")
    func shapeKindIdentity() {
        for kind in MenuBarShapeKind.allCases {
            #expect(kind.id == kind.rawValue)
        }
        #expect(Set(MenuBarShapeKind.allCases.map(\.id)).count == MenuBarShapeKind.allCases.count)
    }

    @Test("A stored shape kind decodes to its case, including the notch")
    func shapeKindDecodes() throws {
        let decoded = try JSONDecoder().decode([MenuBarShapeKind].self, from: Data("[0,1,2,3]".utf8))
        #expect(decoded == [.noShape, .full, .split, .notch])
    }

    @Test("An unknown stored shape kind fails to decode instead of picking a shape")
    func unknownShapeKindThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([MenuBarShapeKind].self, from: Data("[9]".utf8))
        }
    }

    @Test("Border styles are labelled Solid, Dashed and Dotted")
    func borderStyleLabels() {
        #expect(MenuBarBorderStyle.solid.localized == "Solid")
        #expect(MenuBarBorderStyle.dashed.localized == "Dashed")
        #expect(MenuBarBorderStyle.dotted.localized == "Dotted")
    }

    @Test("Recording watch screen choices have their own labels")
    func recordingWatchScreenLabels() {
        #expect(RecordingWatchScreen.screenWithPointer.localized == "Screen with pointer")
        #expect(RecordingWatchScreen.mainDisplay.localized == "Main display")
        #expect(RecordingWatchScreen.display(uuid: "A").localized == "Chosen display")
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

    @Test("Background glass that follows the system takes Regular while Tinted and Clear while Clear")
    func backgroundSystemGlass() {
        var config = MenuBarAppearancePartialConfiguration.defaultConfiguration
        config.backgroundGlassStyle = .liquid
        config.tintGlassStyle = .liquid
        config.backgroundGlassFollowsSystem = true
        #expect(config.withSystemGlass(tinted: true).backgroundGlassStyle == .regular)
        #expect(config.withSystemGlass(tinted: false).backgroundGlassStyle == .clear)
        #expect(config.withSystemGlass(tinted: false).tintGlassStyle == .liquid)
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
