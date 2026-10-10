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
        // The fields the older payload never wrote take the shared default
        // rather than a hardcoded literal, which would misread a deliberate
        // default change as a regression.
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
}
