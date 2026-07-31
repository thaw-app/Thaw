//
//  CoverageSweep1Tests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Thaw

/// Coverage sweep, part 1: the menu bar *appearance* value types.
///
/// Picks up the residue `MenuBarShapesTests`, `MenuBarTintKindTests` and
/// `MenuBarAppearanceConfigurationTests` leave behind:
///
/// - every `localized` switch in `MenuBarShapes.swift`
///   (`MenuBarShapeKind`, `MenuBarBackgroundKind`, `MenuBarGlassStyle`) —
///   these are pure display mappings, but each arm is a separate branch and
///   a mis-wired `case` ships a wrong label,
/// - `MenuBarGlassStyle.nsGlassStyle`, the bridge to AppKit's
///   `NSGlassEffectView.Style`,
/// - `MenuBarShapeKind`'s **custom decoder** rejecting an out-of-range raw
///   value. That decoder is the read side of a persisted format, so its
///   refusal path is load-bearing: silently defaulting instead of throwing
///   would let a corrupt appearance blob resurrect as `noShape`,
/// - `MenuBarAppearanceConfigurationV1.hasRoundedShape` (the legacy Ice
///   format read by `IceSettingsImporter`),
/// - `MenuBarAppearanceConfigurationV2.current`'s dynamic/static selection.
///
/// Deliberate gap: `MenuBarAppearanceConfigurationV2.current` is exercised
/// with *identical* light and dark configurations when `isDynamic` is true,
/// so the assertion holds whichever way `SystemAppearance.current` resolves
/// on the running machine. Which of the two arms runs is therefore not
/// pinned here — only that a dynamic configuration reads from the
/// mode-specific pair rather than from `staticConfiguration`.
@MainActor
@Suite("Coverage sweep 1: menu bar appearance value types")
struct CoverageSweep1Tests {
    // MARK: - MenuBarShapeKind

    @MainActor
    @Suite("MenuBarShapeKind")
    struct ShapeKindTests {
        @Test("Every shape kind has its own label")
        func localizedLabels() {
            #expect(MenuBarShapeKind.noShape.localized == LocalizedStringKey("None"))
            #expect(MenuBarShapeKind.full.localized == LocalizedStringKey("Full"))
            #expect(MenuBarShapeKind.split.localized == LocalizedStringKey("Split"))
            #expect(MenuBarShapeKind.notch.localized == LocalizedStringKey("Notch"))
        }

        @Test("No two shape kinds share a label")
        func localizedLabelsAreDistinct() {
            // `LocalizedStringKey` is Equatable but not Hashable, so this
            // cannot go through a Set.
            let labels = MenuBarShapeKind.allCases.map(\.localized)
            for (offset, label) in labels.enumerated() {
                for other in labels[(offset + 1)...] {
                    #expect(label != other)
                }
            }
        }

        /// The decoder is the read side of `MenuBarAppearanceConfigurationV2`
        /// as it is persisted in `UserDefaults`, so an unknown raw value has
        /// to fail loudly rather than fall back to a shape the user never
        /// chose.
        @Test("An out-of-range raw value is rejected rather than defaulted", arguments: [4, 99, -1])
        func decodingAnUnknownRawValueThrows(_ rawValue: Int) throws {
            let data = try JSONEncoder().encode(rawValue)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(MenuBarShapeKind.self, from: data)
            }
        }

        /// Raw value 3 takes an explicit early-return arm in the decoder
        /// rather than the generic `init(rawValue:)` lookup, so pin that the
        /// two agree.
        @Test("Every in-range raw value decodes to the kind with that raw value", arguments: [0, 1, 2, 3])
        func decodingAnInRangeRawValueMatchesTheRawValueInit(_ rawValue: Int) throws {
            let data = try JSONEncoder().encode(rawValue)
            let decoded = try JSONDecoder().decode(MenuBarShapeKind.self, from: data)
            #expect(decoded == MenuBarShapeKind(rawValue: rawValue))
            #expect(decoded.rawValue == rawValue)
        }
    }

    // MARK: - MenuBarBackgroundKind

    @MainActor
    @Suite("MenuBarBackgroundKind")
    struct BackgroundKindTests {
        @Test("Every background kind has its own label")
        func localizedLabels() {
            #expect(MenuBarBackgroundKind.none.localized == LocalizedStringKey("None"))
            #expect(MenuBarBackgroundKind.solid.localized == LocalizedStringKey("Solid"))
            #expect(MenuBarBackgroundKind.gradient.localized == LocalizedStringKey("Gradient"))
            #expect(MenuBarBackgroundKind.glass.localized == LocalizedStringKey("Glass"))
            #expect(MenuBarBackgroundKind.adaptive.localized == LocalizedStringKey("Adaptive"))
        }

        @Test("No two background kinds share a label")
        func localizedLabelsAreDistinct() {
            let labels = MenuBarBackgroundKind.allCases.map(\.localized)
            for (offset, label) in labels.enumerated() {
                for other in labels[(offset + 1)...] {
                    #expect(label != other)
                }
            }
        }

        /// `defaultKind` is what a configuration falls back to when no
        /// background was ever chosen, so a change here silently restyles
        /// every existing install.
        @Test("The app-level default background is none")
        func defaultKindIsNone() {
            #expect(MenuBarBackgroundKind.defaultKind == MenuBarBackgroundKind.none)
        }
    }

    // MARK: - MenuBarGlassStyle

    @MainActor
    @Suite("MenuBarGlassStyle")
    struct GlassStyleTests {
        @Test("Each style maps to the matching AppKit glass style")
        func nsGlassStyleMapping() {
            #expect(MenuBarGlassStyle.regular.nsGlassStyle == NSGlassEffectView.Style.regular)
            #expect(MenuBarGlassStyle.clear.nsGlassStyle == NSGlassEffectView.Style.clear)
        }

        @Test("The two styles do not collapse onto one AppKit style")
        func nsGlassStyleMappingIsInjective() {
            #expect(MenuBarGlassStyle.regular.nsGlassStyle != MenuBarGlassStyle.clear.nsGlassStyle)
        }

        @Test("Each style has its own label")
        func localizedLabels() {
            #expect(MenuBarGlassStyle.regular.localized == LocalizedStringKey("Regular"))
            #expect(MenuBarGlassStyle.clear.localized == LocalizedStringKey("Clear"))
            #expect(MenuBarGlassStyle.regular.localized != MenuBarGlassStyle.clear.localized)
        }

        /// The style is persisted inside the appearance configuration as its
        /// raw value, so these two integers are a storage format.
        @Test("The raw values are the stored format")
        func rawValuesArePinned() {
            #expect(MenuBarGlassStyle.regular.rawValue == 0)
            #expect(MenuBarGlassStyle.clear.rawValue == 1)
        }
    }

    // MARK: - MenuBarAppearanceConfigurationV1

    @MainActor
    @Suite("MenuBarAppearanceConfigurationV1.hasRoundedShape")
    struct LegacyConfigurationTests {
        private func configuration(
            shapeKind: MenuBarShapeKind,
            fullShapeInfo: MenuBarFullShapeInfo = .defaultValue,
            splitShapeInfo: MenuBarSplitShapeInfo = .defaultValue
        ) -> MenuBarAppearanceConfigurationV1 {
            var configuration = MenuBarAppearanceConfigurationV1.defaultConfiguration
            configuration.shapeKind = shapeKind
            configuration.fullShapeInfo = fullShapeInfo
            configuration.splitShapeInfo = splitShapeInfo
            return configuration
        }

        private var squareFull: MenuBarFullShapeInfo {
            MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
        }

        @Test("A shapeless configuration is never rounded")
        func noShapeIsNeverRounded() {
            // Round end caps are supplied on purpose: `noShape` must ignore
            // them rather than read through to the full-shape info.
            #expect(!configuration(shapeKind: .noShape, fullShapeInfo: .defaultValue).hasRoundedShape)
        }

        @Test("A full shape reads its rounding from the full shape info")
        func fullShapeReadsFullShapeInfo() {
            #expect(configuration(shapeKind: .full, fullShapeInfo: .defaultValue).hasRoundedShape)
            #expect(!configuration(shapeKind: .full, fullShapeInfo: squareFull).hasRoundedShape)
        }

        @Test("A split shape reads its rounding from the split shape info")
        func splitShapeReadsSplitShapeInfo() {
            let squareSplit = MenuBarSplitShapeInfo(leading: squareFull, trailing: squareFull)
            // The full-shape info is left rounded to prove the split arm does
            // not read the wrong field.
            #expect(configuration(shapeKind: .split, splitShapeInfo: .defaultValue).hasRoundedShape)
            #expect(!configuration(shapeKind: .split, splitShapeInfo: squareSplit).hasRoundedShape)
        }

        /// V1 predates the notch shape entirely; the enum case exists only
        /// because it shares `MenuBarShapeKind` with V2, so the legacy
        /// configuration must report it as unrounded rather than guessing.
        @Test("A notch shape is not rounded in the legacy format")
        func notchShapeIsNeverRoundedInV1() {
            #expect(!configuration(shapeKind: .notch).hasRoundedShape)
        }
    }

    // MARK: - MenuBarAppearanceConfigurationV2

    @MainActor
    @Suite("MenuBarAppearanceConfigurationV2.current")
    struct CurrentConfigurationTests {
        private func partial(borderWidth: Double) -> MenuBarAppearancePartialConfiguration {
            var partial = MenuBarAppearancePartialConfiguration.defaultConfiguration
            partial.borderWidth = borderWidth
            return partial
        }

        @Test("A static configuration ignores the light and dark pair")
        func staticConfigurationIsUsedWhenNotDynamic() {
            var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
            configuration.isDynamic = false
            configuration.lightModeConfiguration = partial(borderWidth: 1)
            configuration.darkModeConfiguration = partial(borderWidth: 2)
            configuration.staticConfiguration = partial(borderWidth: 3)

            #expect(configuration.current == configuration.staticConfiguration)
            #expect(configuration.current.borderWidth == 3)
        }

        /// Light and dark are set to the same value so the expectation does
        /// not depend on the appearance of the machine running the suite;
        /// what it pins is that a dynamic configuration reads the pair and
        /// never falls through to `staticConfiguration`.
        @Test("A dynamic configuration reads the mode pair, not the static one")
        func dynamicConfigurationIgnoresTheStaticConfiguration() {
            var configuration = MenuBarAppearanceConfigurationV2.defaultConfiguration
            configuration.isDynamic = true
            configuration.lightModeConfiguration = partial(borderWidth: 7)
            configuration.darkModeConfiguration = partial(borderWidth: 7)
            configuration.staticConfiguration = partial(borderWidth: 42)

            #expect(configuration.current.borderWidth == 7)
            #expect(configuration.current != configuration.staticConfiguration)
        }
    }
}
