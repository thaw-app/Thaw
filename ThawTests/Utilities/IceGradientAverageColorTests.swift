//
//  IceGradientAverageColorTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers `IceGradient.averageColor(using:option:)`.
///
/// The averaging loop divides the summed RGBA components by the number of
/// samples that contributed components. The empty-count guard added next to
/// that division mirrors the one already present in
/// ``CGImage.averageColor``: dividing by a zero count yields a `CGColor`
/// whose components are all `NaN`, which reads as a valid color to every
/// caller and poisons whatever it is blended into.
///
/// That guard is defensive depth. On macOS the samples are produced by
/// interpolating an `NSGradient`, and once the gradient is non-empty the
/// interpolation always returns a color with usable components, so the count
/// is never zero in practice. The cases below therefore lock the two
/// reachable contracts — an empty gradient averages to `nil`, and a
/// non-empty gradient averages to a color with no `NaN`/infinite components
/// — which is the user-visible behavior the guard exists to preserve.
@Suite("IceGradient average color")
@MainActor
struct IceGradientAverageColorTests {
    // MARK: Empty gradient

    @Test("An empty gradient averages to nil")
    func emptyGradientReturnsNil() {
        #expect(IceGradient(stops: []).averageColor() == nil)
    }

    // MARK: Non-empty gradient

    @Test("A non-empty gradient averages to a color with finite components")
    func nonEmptyGradientReturnsFiniteColor() {
        let gradient = IceGradient(stops: [
            .white(location: 0),
            .black(location: 1),
        ])

        let average = gradient.averageColor()
        let components = average?.components ?? []

        // The averaged color must never carry NaN or infinite components,
        // which is the exact failure mode the empty-count guard prevents.
        #expect(average != nil)
        #expect(!components.isEmpty)
        for component in components {
            #expect(component.isFinite)
        }
    }

    @Test("A single-stop gradient still averages to a finite color")
    func singleStopGradientReturnsFiniteColor() {
        let gradient = IceGradient(stops: [.white(location: 0)])

        let average = gradient.averageColor()
        let components = average?.components ?? []

        #expect(average != nil)
        #expect(!components.isEmpty)
        for component in components {
            #expect(component.isFinite)
        }
    }
}
