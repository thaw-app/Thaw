//
//  IceGradientAverageColorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers `IceGradient.averageColor(using:option:)`.
///
/// Dividing by a zero sample count yields an all-`NaN` `CGColor` that reads
/// as valid and poisons whatever it is blended into; the guard mirrors
/// ``CGImage.averageColor``. A non-empty `NSGradient` never yields a zero
/// count, so the cases lock the reachable contracts: an empty gradient
/// averages to `nil`, and a non-empty one has no `NaN` or infinite components.
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
