//
//  CoverageSweep2Tests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import Testing
@testable import Thaw

/// Coverage sweep, part 2: the small presentation-facing value types whose
/// existing suites stopped at raw values and `Codable`.
///
/// Covers:
///
/// - `IceBarLayout` — `id`, `localized`, and the string parser's rejection
///   path. The parser accepts both case names and stringified raw values
///   because it backs the `thaw://` settings URI, so an accepted alias set
///   is part of that public surface.
/// - `IceBarLocation.localized` (`IceBarLocationTests` covers everything
///   else about the type).
/// - `SectionDividerStyle.localized`.
/// - `ControlItemImageSet.id`, which is `hashValue` rather than the name —
///   worth pinning because a `List` selection keyed on it must survive two
///   equal sets colliding.
/// - `NavigationIdentifier`'s *default* `localized`, which no shipping
///   conformer uses: `SettingsNavigationIdentifier` overrides it. The
///   default is exercised through a test-local conformer.
/// - `SecondsLabel` and `GlassIconBubble`'s defaulted members.
///
/// Deliberate gaps: `IceBarLocation.iceIcon`'s label interpolates
/// `Constants.displayName`, so it is asserted to be distinct from its
/// siblings rather than compared against a rebuilt literal — reconstructing
/// the interpolation in the test would only restate the implementation.
@MainActor
@Suite("Coverage sweep 2: bar, divider and navigation display values")
struct CoverageSweep2Tests {
    // MARK: - IceBarLayout

    @MainActor
    @Suite("IceBarLayout")
    struct BarLayoutTests {
        @Test("Every layout's identifier is its raw value")
        func idMatchesRawValue() {
            for layout in IceBarLayout.allCases {
                #expect(layout.id == layout.rawValue)
            }
        }

        @Test("Every layout has its own label")
        func localizedLabels() {
            #expect(IceBarLayout.horizontal.localized == LocalizedStringKey("Horizontal"))
            #expect(IceBarLayout.vertical.localized == LocalizedStringKey("Vertical"))
            #expect(IceBarLayout.grid.localized == LocalizedStringKey("Grid"))
        }

        @Test("No two layouts share a label")
        func localizedLabelsAreDistinct() {
            // `LocalizedStringKey` is Equatable but not Hashable, so this
            // cannot go through a Set.
            let labels = IceBarLayout.allCases.map(\.localized)
            for (offset, label) in labels.enumerated() {
                for other in labels[(offset + 1)...] {
                    #expect(label != other)
                }
            }
        }

        /// `fromString` backs `thaw://set?key=iceBarLayout&value=…`, so both
        /// spellings are an external contract.
        @Test(
            "Both the case name and the raw value parse to the same layout",
            arguments: zip(["horizontal", "vertical", "grid"], [IceBarLayout.horizontal, .vertical, .grid])
        )
        func fromStringAcceptsNameAndRawValue(_ name: String, _ expected: IceBarLayout) {
            #expect(IceBarLayout.fromString(name) == expected)
            #expect(IceBarLayout.fromString(String(expected.rawValue)) == expected)
        }

        @Test(
            "An unknown spelling is rejected rather than defaulted",
            arguments: ["", "Horizontal", "HORIZONTAL", "3", "-1", "column", " grid"]
        )
        func fromStringRejectsUnknownSpellings(_ candidate: String) {
            #expect(IceBarLayout.fromString(candidate) == nil)
        }
    }

    // MARK: - IceBarLocation

    @MainActor
    @Suite("IceBarLocation labels")
    struct BarLocationTests {
        @Test("The fixed labels are the documented ones")
        func localizedLabels() {
            #expect(IceBarLocation.dynamic.localized == LocalizedStringKey("Dynamic"))
            #expect(IceBarLocation.mousePointer.localized == LocalizedStringKey("Mouse pointer"))
            #expect(IceBarLocation.leftAligned.localized == LocalizedStringKey("Left aligned"))
            #expect(IceBarLocation.rightAligned.localized == LocalizedStringKey("Right aligned"))
        }

        @Test("No two locations share a label")
        func localizedLabelsAreDistinct() {
            let labels = IceBarLocation.allCases.map(\.localized)
            for (offset, label) in labels.enumerated() {
                for other in labels[(offset + 1)...] {
                    #expect(label != other)
                }
            }
        }
    }

    // MARK: - SectionDividerStyle

    @MainActor
    @Suite("SectionDividerStyle labels")
    struct DividerStyleTests {
        @Test("Each style has its own label")
        func localizedLabels() {
            #expect(SectionDividerStyle.noDivider.localized == LocalizedStringKey("None"))
            #expect(SectionDividerStyle.chevron.localized == LocalizedStringKey("Chevron"))
            #expect(SectionDividerStyle.noDivider.localized != SectionDividerStyle.chevron.localized)
        }
    }

    // MARK: - ControlItemImageSet

    @MainActor
    @Suite("ControlItemImageSet identity")
    struct ImageSetTests {
        @Test("The identifier is the hash of the whole set, not just its name")
        func idIsTheHashValue() {
            let set = ControlItemImageSet.defaultIceIcon
            #expect(set.id == set.hashValue)
        }

        @Test("Two sets that differ only in their images get different identifiers")
        func differingImagesGetDifferentIdentifiers() {
            let first = ControlItemImageSet(name: .dot, image: .catalog("DotFill"))
            let second = ControlItemImageSet(name: .dot, image: .catalog("DotStroke"))
            #expect(first.id != second.id)
        }

        @Test("Two identical sets share an identifier")
        func identicalSetsShareAnIdentifier() {
            let first = ControlItemImageSet(name: .dot, image: .catalog("DotFill"))
            let second = ControlItemImageSet(name: .dot, hidden: .catalog("DotFill"), visible: .catalog("DotFill"))
            #expect(first == second)
            #expect(first.id == second.id)
        }
    }

    // MARK: - NavigationIdentifier

    @MainActor
    @Suite("NavigationIdentifier default label")
    struct NavigationIdentifierTests {
        /// `SettingsNavigationIdentifier` supplies its own `localized`, so
        /// the protocol's `RawValue == String` default is only reachable
        /// through a conformer that does not. This exists to prove the
        /// default keeps working for the next such conformer.
        @Test("A String-raw conformer labels itself with its raw value")
        func defaultLocalizedUsesTheRawValue() {
            #expect(SweepNavigationIdentifier.first.localized == LocalizedStringKey("First Destination"))
            #expect(SweepNavigationIdentifier.second.localized == LocalizedStringKey("Second Destination"))
        }

        @Test("The shipping conformer overrides the default rather than inheriting it")
        func settingsIdentifierOverridesTheDefault() {
            // `menuBarLayout`'s raw value is its persisted name; its label is
            // the short sidebar title. If the override were ever dropped the
            // sidebar would start reading "Menu Bar Layout".
            #expect(SettingsNavigationIdentifier.menuBarLayout.rawValue == "Menu Bar Layout")
            #expect(SettingsNavigationIdentifier.menuBarLayout.localized == LocalizedStringKey("Layout"))
        }
    }

    // MARK: - Small view value types

    @MainActor
    @Suite("Small view value types")
    struct ViewValueTests {
        @Test("A seconds label's text depends on its value")
        func secondsLabelTextTracksItsValue() {
            #expect(SecondsLabel(value: 1.5).body == SecondsLabel(value: 1.5).body)
            #expect(SecondsLabel(value: 1.5).body != SecondsLabel(value: 2.5).body)
        }

        /// The onboarding mockups construct these without arguments and rely
        /// on the defaults matching a real menu bar glyph.
        @Test("A glass icon bubble takes the documented defaults")
        func glassIconBubbleDefaults() {
            let bubble = GlassIconBubble(symbol: "gear")
            #expect(bubble.symbol == "gear")
            #expect(bubble.size == 30)
            #expect(bubble.tint == Color.primary)
            #expect(bubble.showBackground)
        }

        @Test("Explicit values override the glass icon bubble defaults")
        func glassIconBubbleExplicitValues() {
            let bubble = GlassIconBubble(symbol: "star", size: 12, tint: .red, showBackground: false)
            #expect(bubble.size == 12)
            #expect(bubble.tint == Color.red)
            #expect(!bubble.showBackground)
        }
    }
}

// MARK: - Test-local NavigationIdentifier conformer

/// A conformer that deliberately does **not** override `localized`, so the
/// protocol extension's `RawValue == String` default is what runs.
private enum SweepNavigationIdentifier: String, NavigationIdentifier {
    typealias ID = Int

    case first = "First Destination"
    case second = "Second Destination"

    var iconResource: IconResource {
        .systemSymbol("gearshape")
    }
}
