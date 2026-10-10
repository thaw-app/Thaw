//
//  SharedAppearanceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@Suite("Shared appearance payload")
struct SharedAppearanceTests {
    private func shared(
        _ configuration: MenuBarAppearancePartialConfiguration,
        shape: MenuBarShapeKind = .full,
        isDark: Bool = false
    ) -> SharedAppearance {
        SharedAppearance(configuration: configuration, shapeKind: shape, hasRoundedShape: true, isDark: isDark)
    }

    private func json(_ appearance: SharedAppearance) throws -> [String: Any] {
        let data = try JSONEncoder().encode(appearance)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("The payload names its version, scheme and shape")
    func carriesVersionSchemeAndShape() throws {
        let object = try json(shared(.defaultConfiguration, shape: .notch, isDark: true))
        #expect(object["version"] as? Int == SharedAppearance.currentVersion)
        #expect(object["colorScheme"] as? String == "dark")
        #expect(object["shape"] as? String == "notch")
        #expect(object["hasRoundedShape"] as? Bool == true)
    }

    @Test("A solid tint carries its color in sRGB and no gradient or glass fields")
    func solidTintCarriesColorOnly() throws {
        var configuration = MenuBarAppearancePartialConfiguration.defaultConfiguration
        configuration.tintKind = .solid
        configuration.tintColor = CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)
        configuration.tintOpacity = 0.4

        let tint = shared(configuration).tint
        #expect(tint.kind == "solid")
        #expect(tint.opacity == 0.4)
        #expect(tint.color?.red == 1)
        #expect(tint.color?.green == 0.5)
        #expect(tint.stops == nil)
        #expect(tint.glassStyle == nil)
    }

    @Test("A gradient fill carries its stops in order")
    func gradientCarriesStops() {
        var configuration = MenuBarAppearancePartialConfiguration.defaultConfiguration
        configuration.backgroundKind = .gradient
        configuration.backgroundGradient = ThawGradient(stops: [
            .stop(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), location: 0),
            .stop(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), location: 1),
        ])

        let background = shared(configuration).background
        #expect(background.kind == "gradient")
        #expect(background.stops?.map(\.location) == [0, 1])
        #expect(background.stops?.first?.color.red == 1)
        #expect(background.color == nil)
    }

    @Test("A gradient fill carries its angle, and other fills carry none")
    func gradientCarriesAngle() {
        var configuration = MenuBarAppearancePartialConfiguration.defaultConfiguration
        configuration.backgroundKind = .gradient
        #expect(shared(configuration).background.angle == 90)

        configuration.backgroundGradient.angle = 0
        #expect(shared(configuration).background.angle == 0)

        configuration.backgroundKind = .solid
        #expect(shared(configuration).background.angle == nil)
    }

    @Test("Glass names its style, and keeps its color only when colored")
    func glassCarriesStyle() {
        var configuration = MenuBarAppearancePartialConfiguration.defaultConfiguration
        configuration.backgroundKind = .glass
        configuration.backgroundGlassStyle = .clear
        configuration.backgroundGlassIsColored = false
        #expect(shared(configuration).background.glassStyle == "clear")
        #expect(shared(configuration).background.color == nil)

        configuration.backgroundGlassIsColored = true
        #expect(shared(configuration).background.glassIsColored == true)
        #expect(shared(configuration).background.color != nil)
    }

    @Test("A border that is off is left out")
    func borderIsOmittedWhenOff() throws {
        var configuration = MenuBarAppearancePartialConfiguration.defaultConfiguration
        configuration.hasBorder = false
        #expect(shared(configuration).border == nil)
        #expect(try json(shared(configuration))["border"] == nil)

        configuration.hasBorder = true
        configuration.borderWidth = 2
        configuration.borderStyle = .dashed
        #expect(shared(configuration).border?.width == 2)
        #expect(shared(configuration).border?.style == "dashed")
    }
}
