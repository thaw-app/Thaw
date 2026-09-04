//
//  MenuBarTintKindTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import Testing
@testable import Thaw

/// Covers ``MenuBarTintKind``, the stored discriminator for how the menu bar
/// overlay is tinted.
///
/// The raw values are a persisted format: they sit inside every encoded
/// `MenuBarAppearancePartialConfiguration`, in the Thaw Bar's per-display
/// configurations, and in profiles exported by earlier builds. Reordering the
/// cases would silently repaint a user's menu bar — `.gradient` becoming
/// `.glass` costs nothing at compile time — so the raw values are pinned here
/// rather than left to declaration order.
///
/// The hand-written `init(from:)` is the other half. It exists specifically to
/// reject a raw value this build does not know, which is what a downgrade from
/// a future release produces. Decoding has to throw there rather than fall back
/// to `.noTint`, otherwise a downgrade-then-upgrade round trip silently
/// discards the user's tint choice.
@MainActor
@Suite("Menu bar tint kind")
struct MenuBarTintKindTests {
    // MARK: - Stored Format

    @Test("Raw values are pinned to their stored form")
    func rawValuesArePinned() {
        #expect(MenuBarTintKind.noTint.rawValue == 0)
        #expect(MenuBarTintKind.solid.rawValue == 1)
        #expect(MenuBarTintKind.gradient.rawValue == 2)
        #expect(MenuBarTintKind.glass.rawValue == 3)
        #expect(MenuBarTintKind.adaptive.rawValue == 4)
        #expect(MenuBarTintKind.adaptiveGradient.rawValue == 5)
    }

    @Test("Every case is reachable and no case has been dropped")
    func allCasesIsComplete() {
        #expect(MenuBarTintKind.allCases.count == 6)
        #expect(MenuBarTintKind.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
    }

    @Test("A case is identified by its raw value", arguments: MenuBarTintKind.allCases)
    func identifierMatchesRawValue(_ kind: MenuBarTintKind) {
        #expect(kind.id == kind.rawValue)
    }

    @Test("Identifiers are unique across the cases")
    func identifiersAreUnique() {
        let identifiers = MenuBarTintKind.allCases.map(\.id)

        #expect(Set(identifiers).count == MenuBarTintKind.allCases.count)
    }

    @Test("A raw value outside the known range produces no case")
    func unknownRawValueProducesNoCase() {
        #expect(MenuBarTintKind(rawValue: -1) == nil)
        #expect(MenuBarTintKind(rawValue: 6) == nil)
    }

    // MARK: - Adaptivity

    @Test("Only the wallpaper-derived kinds report as adaptive")
    func isAdaptiveCoversTheWallpaperKinds() {
        #expect(MenuBarTintKind.adaptive.isAdaptive)
        #expect(MenuBarTintKind.adaptiveGradient.isAdaptive)
        #expect(!MenuBarTintKind.noTint.isAdaptive)
        #expect(!MenuBarTintKind.solid.isAdaptive)
        #expect(!MenuBarTintKind.gradient.isAdaptive)
        #expect(!MenuBarTintKind.glass.isAdaptive)
    }

    // MARK: - Localization

    @Test("Each case maps to its shipped localized key")
    func localizedKeysMatchTheShippedStrings() {
        #expect(MenuBarTintKind.noTint.localized == LocalizedStringKey("None"))
        #expect(MenuBarTintKind.solid.localized == LocalizedStringKey("Solid"))
        #expect(MenuBarTintKind.gradient.localized == LocalizedStringKey("Gradient"))
        #expect(MenuBarTintKind.glass.localized == LocalizedStringKey("Glass"))
        #expect(MenuBarTintKind.adaptive.localized == LocalizedStringKey("Adaptive"))
        #expect(MenuBarTintKind.adaptiveGradient.localized == LocalizedStringKey("Adaptive Gradient"))
    }

    /// The picker rows are built straight from `allCases`, so two cases sharing
    /// a key would render as duplicate rows.
    @Test("No two cases share a localized key")
    func localizedKeysAreDistinct() {
        // `LocalizedStringKey` is Equatable but not Hashable, so this compares
        // pairwise rather than going through a Set.
        let keys = MenuBarTintKind.allCases.map(\.localized)

        for (offset, key) in keys.enumerated() {
            let collides = keys.enumerated().contains { other in
                other.offset != offset && other.element == key
            }
            #expect(!collides, "two tint kinds share a localized key at index \(offset)")
        }
    }

    // MARK: - Codable

    @Test("Every case survives a round trip", arguments: MenuBarTintKind.allCases)
    func caseSurvivesARoundTrip(_ kind: MenuBarTintKind) throws {
        let data = try JSONEncoder().encode([kind])
        let decoded = try JSONDecoder().decode([MenuBarTintKind].self, from: data)

        #expect(decoded == [kind])
    }

    @Test("A case encodes as its bare raw value")
    func caseEncodesAsItsBareRawValue() throws {
        let data = try JSONEncoder().encode([MenuBarTintKind.adaptive])

        #expect(String(decoding: data, as: UTF8.self) == "[4]")
    }

    @Test("A stored raw value decodes to the matching case")
    func storedRawValueDecodesToTheMatchingCase() throws {
        let data = Data("[0,1,2,3,4,5]".utf8)
        let decoded = try JSONDecoder().decode([MenuBarTintKind].self, from: data)

        #expect(decoded == MenuBarTintKind.allCases)
    }

    /// A raw value from a future build has to fail loudly rather than resolve
    /// to a neighbouring case.
    @Test("An unknown raw value is rejected rather than defaulted")
    func unknownRawValueIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([MenuBarTintKind].self, from: Data("[99]".utf8))
        }
    }

    @Test("A negative raw value is rejected")
    func negativeRawValueIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([MenuBarTintKind].self, from: Data("[-1]".utf8))
        }
    }

    @Test("A non-integer payload is rejected")
    func nonIntegerPayloadIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([MenuBarTintKind].self, from: Data("[\"solid\"]".utf8))
        }
    }

    /// The rejection is a `dataCorrupted` error specifically, which is what the
    /// callers that recover from a bad payload match on.
    @Test("The rejection is reported as corrupted data")
    func rejectionIsReportedAsCorruptedData() throws {
        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([MenuBarTintKind].self, from: Data("[99]".utf8))
        }

        guard case .dataCorrupted = try #require(error) else {
            Issue.record("expected a dataCorrupted error, got \(String(describing: error))")
            return
        }
    }
}
