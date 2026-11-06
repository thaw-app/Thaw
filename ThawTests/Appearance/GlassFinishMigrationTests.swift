//
//  GlassFinishMigrationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Testing
@testable import Thaw

/// Glass finishes saved by older builds, which had Clear, Liquid Glass and
/// Match System, open as the current Glass, Tint and Liquid Glass choices.
@MainActor
@Suite("Glass finish migration")
struct GlassFinishMigrationTests {
    /// A stored finish from an older build and the finish it opens as.
    nonisolated struct LegacyCase: CustomTestStringConvertible, Sendable {
        let rawValue: Int
        let followsSystem: Bool
        let style: MenuBarGlassStyle
        let isTinted: Bool

        var testDescription: String {
            "\(rawValue)\(followsSystem ? " following the system" : "") opens as \(style)\(isTinted ? " with Tint" : "")"
        }
    }

    static nonisolated let legacyCases: [LegacyCase] = [
        LegacyCase(rawValue: 0, followsSystem: false, style: .regular, isTinted: false),
        LegacyCase(rawValue: 1, followsSystem: false, style: .regular, isTinted: false),
        LegacyCase(rawValue: 2, followsSystem: false, style: .regular, isTinted: true),
        LegacyCase(rawValue: 3, followsSystem: false, style: .dynamic, isTinted: false),
        LegacyCase(rawValue: 4, followsSystem: false, style: .solid, isTinted: false),
        LegacyCase(rawValue: 5, followsSystem: false, style: .edge, isTinted: false),
        LegacyCase(rawValue: 6, followsSystem: false, style: .sheer, isTinted: false),
        LegacyCase(rawValue: 7, followsSystem: false, style: .dim, isTinted: false),
        // Match System stored whichever of Regular and Clear the system last chose.
        LegacyCase(rawValue: 0, followsSystem: true, style: .regular, isTinted: false),
        LegacyCase(rawValue: 1, followsSystem: true, style: .regular, isTinted: false),
        LegacyCase(rawValue: 2, followsSystem: true, style: .regular, isTinted: false),
    ]

    private func jsonObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Rewrites the glass keys of an encoded look the way an older build stored them.
    private func legacy(_ object: [String: Any], _ legacyCase: LegacyCase) -> [String: Any] {
        var object = object
        for surface in ["background", "tint"] {
            object["\(surface)GlassStyle"] = legacyCase.rawValue
            object["\(surface)GlassFollowsSystem"] = legacyCase.followsSystem
            object.removeValue(forKey: "\(surface)GlassIsTinted")
        }
        return object
    }

    private func decode<Value: Decodable>(_: Value.Type, from object: [String: Any]) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test("An older menu bar look opens with the new finish", arguments: legacyCases)
    func menuBarLook(legacyCase: LegacyCase) throws {
        let stored = try legacy(jsonObject(MenuBarAppearancePartialConfiguration.defaultConfiguration), legacyCase)
        let decoded = try decode(MenuBarAppearancePartialConfiguration.self, from: stored)
        let expected = MenuBarGlassFinish(style: legacyCase.style, isTinted: legacyCase.isTinted)
        #expect(decoded.backgroundGlassFinish == expected)
        #expect(decoded.tintGlassFinish == expected)
    }

    @Test("An older Thaw Bar look opens with the new finish", arguments: legacyCases)
    func thawBarLook(legacyCase: LegacyCase) throws {
        var appearance = ThawBarAppearance.defaultConfiguration
        appearance.overridesMenuBar = true
        let stored = try legacy(jsonObject(appearance), legacyCase)
        let decoded = try decode(ThawBarAppearance.self, from: stored)
        let expected = MenuBarGlassFinish(style: legacyCase.style, isTinted: legacyCase.isTinted)
        #expect(decoded.fillConfiguration.backgroundGlassFinish == expected)
        #expect(decoded.fillConfiguration.tintGlassFinish == expected)
        #expect(decoded.overridesMenuBar)
    }

    @Test("An older profile opens with the new finish in every mode and in the Thaw Bar", arguments: legacyCases)
    func profile(legacyCase: LegacyCase) throws {
        let configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
        var appearance = try jsonObject(configuration)
        for key in ["staticConfiguration", "lightModeConfiguration", "darkModeConfiguration", "thawBarAppearance"] {
            appearance[key] = try legacy(#require(appearance[key] as? [String: Any]), legacyCase)
        }
        let profile = try decode(Profile.self, from: ["name": "Old", "appearanceConfiguration": appearance])
        let decoded = profile.appearanceConfiguration
        let expected = MenuBarGlassFinish(style: legacyCase.style, isTinted: legacyCase.isTinted)
        for fill in [
            decoded.staticConfiguration,
            decoded.lightModeConfiguration,
            decoded.darkModeConfiguration,
            decoded.thawBarAppearance.fillConfiguration,
        ] {
            #expect(fill.backgroundGlassFinish == expected)
            #expect(fill.tintGlassFinish == expected)
        }
    }

    @Test("Liquid Glass keeps its color and is drawn as before")
    func liquidGlassLooksTheSame() throws {
        var object = try legacy(
            jsonObject(MenuBarAppearancePartialConfiguration.defaultConfiguration),
            LegacyCase(rawValue: 2, followsSystem: false, style: .regular, isTinted: true)
        )
        object["tintGlassIsColored"] = true
        let decoded = try decode(MenuBarAppearancePartialConfiguration.self, from: object)
        let finish = decoded.tintGlassFinish
        #expect(decoded.tintGlassIsColored)
        #expect(finish.usesTint && finish.usesShapeAwareSurface && !finish.usesDarkFade)
        #expect(finish.effectOpacity == 0.45)
        #expect(finish.nsGlassStyle == .clear)
        #expect(finish.privateVariant == nil)
    }

    @Test("The new form is written and read back, with no Match System keys")
    func newFormRoundTrips() throws {
        var configuration = MenuBarAppearancePartialConfiguration.defaultConfiguration
        configuration.backgroundGlassFinish = MenuBarGlassFinish(style: .regular, isTinted: true)
        configuration.tintGlassFinish = MenuBarGlassFinish(style: .edge, isTinted: false)
        let object = try jsonObject(configuration)
        #expect(object["backgroundGlassStyle"] as? Int == 0)
        #expect(object["backgroundGlassIsTinted"] as? Bool == true)
        #expect(object["tintGlassStyle"] as? Int == 5)
        #expect(object["tintGlassIsTinted"] as? Bool == false)
        #expect(object["backgroundGlassFollowsSystem"] == nil && object["tintGlassFollowsSystem"] == nil)
        let decoded = try decode(MenuBarAppearancePartialConfiguration.self, from: object)
        #expect(decoded.backgroundGlassFinish == configuration.backgroundGlassFinish)
        #expect(decoded.tintGlassFinish == configuration.tintGlassFinish)

        var appearance = ThawBarAppearance.defaultConfiguration
        appearance.fillConfiguration = configuration
        let thawBar = try JSONDecoder().decode(ThawBarAppearance.self, from: JSONEncoder().encode(appearance))
        #expect(thawBar.fillConfiguration.backgroundGlassFinish == configuration.backgroundGlassFinish)
        #expect(thawBar.fillConfiguration.tintGlassFinish == configuration.tintGlassFinish)
    }

    @Test("A stored Tint setting wins over what the finish number implies")
    func storedTintWins() throws {
        var object = try legacy(
            jsonObject(MenuBarAppearancePartialConfiguration.defaultConfiguration),
            LegacyCase(rawValue: 2, followsSystem: false, style: .regular, isTinted: true)
        )
        object["backgroundGlassIsTinted"] = false
        object.removeValue(forKey: "backgroundGlassStyle")
        object["tintGlassIsTinted"] = true
        object["tintGlassStyle"] = 0
        let decoded = try decode(MenuBarAppearancePartialConfiguration.self, from: object)
        #expect(decoded.backgroundGlassFinish == MenuBarGlassFinish(style: .regular, isTinted: false))
        #expect(decoded.tintGlassFinish == MenuBarGlassFinish(style: .regular, isTinted: true))
    }

    @Test("Tint changes only plain glass: Dynamic Glass always takes one and the Alpha finishes never do")
    func tintAppliesToPlainGlass() {
        let plain = MenuBarGlassFinish(style: .regular, isTinted: false)
        #expect(!plain.usesTint && plain.effectOpacity == 1 && plain.nsGlassStyle == .regular)
        for isTinted in [false, true] {
            let dynamic = MenuBarGlassFinish(style: .dynamic, isTinted: isTinted)
            #expect(dynamic.usesTint && dynamic.usesDarkFade && dynamic.effectOpacity == 0.45)
            for style in [MenuBarGlassStyle.solid, .edge, .sheer, .dim] {
                let finish = MenuBarGlassFinish(style: style, isTinted: isTinted)
                #expect(!finish.usesTint && !finish.usesShapeAwareSurface && finish.effectOpacity == 1)
            }
        }
    }
}
