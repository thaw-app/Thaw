//
//  WallpaperPaletteTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Wallpaper palette")
struct WallpaperPaletteTests {
    private typealias Sample = WallpaperPalette.Sample

    private static let red = Sample(red: 1, green: 0, blue: 0)
    private static let green = Sample(red: 0, green: 1, blue: 0)
    private static let blue = Sample(red: 0, green: 0, blue: 1)
    private static let white = Sample(red: 1, green: 1, blue: 1)

    private func samples(_ pairs: [(Sample, Int)]) -> [Sample] {
        pairs.flatMap { Array(repeating: $0.0, count: $0.1) }
    }

    // MARK: Ordering

    @Test("Swatches come back most-covering first")
    func ordersByCoverage() {
        let palette = WallpaperPalette.derive(from: samples([
            (Self.red, 10),
            (Self.green, 50),
            (Self.blue, 30),
        ]))

        let leading = palette.swatches.map { ($0.red, $0.green, $0.blue) }
        #expect(leading.count == 3)
        #expect(leading[0].1 == 1) // green
        #expect(leading[1].2 == 1) // blue
        #expect(leading[2].0 == 1) // red
    }

    @Test("Weights are the fraction of the image each swatch covers")
    func weightsAreCoverageFractions() {
        let palette = WallpaperPalette.derive(from: samples([
            (Self.green, 75),
            (Self.red, 25),
        ]))

        #expect(palette.swatches.count == 2)
        #expect(abs(palette.swatches[0].weight - 0.75) < 0.0001)
        #expect(abs(palette.swatches[1].weight - 0.25) < 0.0001)
    }

    // MARK: Separation

    @Test("Near-identical colors collapse to one swatch")
    func nearDuplicatesAreRejected() {
        // A sky: many blues a viewer would call the same blue. Without the
        // separation step this returns five of them and a gradient built
        // from it looks like a flat fill.
        let skyish = (0 ..< 5).map { index in
            Sample(red: 0.1, green: 0.2, blue: 0.8 + Double(index) * 0.01)
        }
        let palette = WallpaperPalette.derive(from: samples(skyish.map { ($0, 20) }))

        #expect(palette.swatches.count == 1)
    }

    @Test("Genuinely different colors all survive")
    func distinctColorsAreKept() {
        let palette = WallpaperPalette.derive(from: samples([
            (Self.red, 40),
            (Self.green, 30),
            (Self.blue, 20),
        ]))

        #expect(palette.swatches.count == 3)
    }

    @Test("A separation of zero keeps the raw most-populous buckets")
    func zeroSeparationKeepsEverything() {
        let skyish = (0 ..< 4).map { index in
            Sample(red: 0.1, green: 0.2, blue: 0.5 + Double(index) * 0.08)
        }
        let palette = WallpaperPalette.derive(
            from: samples(skyish.map { ($0, 20) }),
            minimumSeparation: 0
        )

        #expect(palette.swatches.count == 4)
    }

    // MARK: Limits

    @Test("No more than the requested number of swatches comes back")
    func respectsMaximumCount() {
        let palette = WallpaperPalette.derive(
            from: samples([(Self.red, 40), (Self.green, 30), (Self.blue, 20), (Self.white, 10)]),
            maximumCount: 2
        )

        #expect(palette.swatches.count == 2)
    }

    @Test("An empty image yields an empty palette rather than a fabricated color")
    func emptyInputYieldsEmptyPalette() {
        let palette = WallpaperPalette.derive(from: [])
        #expect(palette.swatches.isEmpty)
        #expect(palette.primary == nil)
        #expect(palette.secondary == nil)
    }

    @Test("Asking for no swatches yields none")
    func zeroMaximumYieldsEmptyPalette() {
        let palette = WallpaperPalette.derive(
            from: samples([(Self.red, 10)]),
            maximumCount: 0
        )
        #expect(palette.swatches.isEmpty)
    }

    // MARK: Pairing

    @Test("A single-color wallpaper still yields a usable pair")
    func secondaryFallsBackToPrimary() {
        let palette = WallpaperPalette.derive(from: samples([(Self.blue, 100)]))

        #expect(palette.swatches.count == 1)
        // A gradient needs two stops. Repeating the one colour reads as a
        // flat tint, which is right; returning nil would drop the tint.
        #expect(palette.secondary == palette.primary)
    }

    @Test("Primary and secondary are the two most-covering swatches")
    func pairIsTheTopTwo() {
        let palette = WallpaperPalette.derive(from: samples([
            (Self.red, 10),
            (Self.green, 50),
            (Self.blue, 30),
        ]))

        #expect(palette.primary?.green == 1)
        #expect(palette.secondary?.blue == 1)
    }

    // MARK: Determinism

    @Test("Equal-population colors resolve the tie the same way every time")
    func tiesAreBrokenDeterministically() {
        let input = samples([(Self.red, 25), (Self.green, 25), (Self.blue, 25)])
        let first = WallpaperPalette.derive(from: input)
        for _ in 0 ..< 20 {
            #expect(WallpaperPalette.derive(from: input) == first)
        }
    }

    @Test("Sample order does not change the palette")
    func orderDoesNotMatter() {
        let input = samples([(Self.red, 30), (Self.green, 50), (Self.blue, 20)])
        #expect(WallpaperPalette.derive(from: input) == WallpaperPalette.derive(from: input.reversed()))
    }

    // MARK: Swatch behaviour

    @Test("A swatch averages within its bucket rather than snapping to a grid")
    func swatchAveragesItsBucket() {
        // Two samples close enough to share a bucket: the swatch should sit
        // between them, not on a quantization boundary.
        let palette = WallpaperPalette.derive(from: [
            Sample(red: 0.500, green: 0.5, blue: 0.5),
            Sample(red: 0.510, green: 0.5, blue: 0.5),
        ])

        let swatch = try? #require(palette.primary)
        #expect(swatch != nil)
        if let swatch {
            #expect(swatch.red > 0.5 && swatch.red < 0.51)
        }
    }

    @Test("Brightness matches the weighting used elsewhere in the app")
    func brightnessUsesTheSharedWeighting() {
        let palette = WallpaperPalette.derive(from: samples([(Self.white, 10)]))
        #expect(abs((palette.primary?.brightness ?? 0) - 1) < 0.0001)

        let dark = WallpaperPalette.derive(from: samples([
            (Sample(red: 0, green: 0, blue: 0), 10),
        ]))
        #expect(abs(dark.primary?.brightness ?? 1) < 0.0001)
    }

    @Test("Fully saturated components do not overflow into a wrong bucket")
    func fullValueComponentsAreBucketed() {
        // A component of exactly 1 scales to the level count, one past the
        // top bucket, so it has to be clamped or it collides with black.
        let palette = WallpaperPalette.derive(from: samples([(Self.white, 10)]))
        #expect(palette.swatches.count == 1)
        #expect(abs((palette.primary?.red ?? 0) - 1) < 0.0001)
        #expect(abs((palette.primary?.blue ?? 0) - 1) < 0.0001)
    }
}
