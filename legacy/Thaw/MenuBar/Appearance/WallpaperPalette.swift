//
//  WallpaperPalette.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// The dominant colors of an image, ordered by how much of it they cover.
///
/// An average turns a sunset into brown; a palette keeps the colours that
/// actually occupy the image.
///
/// Pure and deterministic so it can be tested without a screen. Pixel reading
/// lives in ``CGImage/dominantColors(maximumCount:)``.
nonisolated struct WallpaperPalette: Equatable {
    struct Swatch: Equatable {
        /// Components in the 0...1 range.
        let red: Double
        let green: Double
        let blue: Double

        /// The fraction of the sampled image this swatch covers, 0...1.
        let weight: Double

        /// Perceived brightness, using the same W3C weighting as the rest
        /// of the app.
        var brightness: Double {
            ((red * 299) + (green * 587) + (blue * 114)) / 1000
        }

        func cgColor(in colorSpace: CGColorSpace) -> CGColor? {
            CGColor(
                colorSpace: colorSpace,
                components: [CGFloat(red), CGFloat(green), CGFloat(blue), 1]
            )
        }

        /// RGB distance. Not perceptually uniform, but good enough to reject
        /// near-duplicates and easy to test.
        func distance(to other: Swatch) -> Double {
            let dr = red - other.red
            let dg = green - other.green
            let db = blue - other.blue
            return (dr * dr + dg * dg + db * db).squareRoot()
        }
    }

    /// A single observed pixel, components in the 0...1 range.
    struct Sample: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    /// Most-covering first. May be empty.
    let swatches: [Swatch]

    var primary: Swatch? {
        swatches.first
    }

    /// The second most-covering swatch, falling back to ``primary`` so a
    /// single-colour wallpaper still yields a usable pair.
    var secondary: Swatch? {
        swatches.count > 1 ? swatches[1] : primary
    }

    /// Buckets per channel. Finer splits smooth gradients into near-identical
    /// buckets; coarser merges colours a viewer would call different.
    private static let levelsPerChannel = 32

    /// Derives a palette from raw samples.
    ///
    /// Takes buckets most-populous first, skipping any too close to one
    /// already taken, so a sky photo doesn't return five blues.
    ///
    /// - Parameters:
    ///   - samples: The observed pixels. Order does not matter.
    ///   - maximumCount: The most swatches to return.
    ///   - minimumSeparation: How far apart two swatches must be, as an RGB
    ///     distance. Zero returns the raw most-populous buckets.
    static func derive(
        from samples: [Sample],
        maximumCount: Int = 5,
        minimumSeparation: Double = 0.25
    ) -> WallpaperPalette {
        guard maximumCount > 0, !samples.isEmpty else {
            return WallpaperPalette(swatches: [])
        }

        let levels = levelsPerChannel
        var counts: [Int: Int] = [:]
        var totals: [Int: (r: Double, g: Double, b: Double)] = [:]

        for sample in samples {
            let key = bucketKey(for: sample, levels: levels)
            counts[key, default: 0] += 1
            var total = totals[key] ?? (0, 0, 0)
            total.r += sample.red
            total.g += sample.green
            total.b += sample.blue
            totals[key] = total
        }

        let sampleCount = Double(samples.count)
        // Sort by population, breaking ties on the bucket key so the result
        // is stable rather than dependent on dictionary ordering.
        let ranked = counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }

        var result: [Swatch] = []
        for (key, count) in ranked {
            guard result.count < maximumCount else { break }
            guard let total = totals[key] else { continue }
            // Average within the bucket rather than using the bucket centre,
            // so the swatch is a colour that actually appears in the image.
            let population = Double(count)
            let swatch = Swatch(
                red: total.r / population,
                green: total.g / population,
                blue: total.b / population,
                weight: population / sampleCount
            )
            if result.contains(where: { $0.distance(to: swatch) < minimumSeparation }) {
                continue
            }
            result.append(swatch)
        }

        return WallpaperPalette(swatches: result)
    }

    private static func bucketKey(for sample: Sample, levels: Int) -> Int {
        func level(_ value: Double) -> Int {
            let scaled = Int(value.clamped(to: 0 ... 1) * Double(levels))
            // A component of exactly 1 would land one past the top bucket.
            return min(scaled, levels - 1)
        }
        return (level(sample.red) * levels * levels)
            + (level(sample.green) * levels)
            + level(sample.blue)
    }
}
