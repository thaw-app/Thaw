//
//  WallpaperPalette.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// The dominant colors of an image, ordered by how much of it they cover.
///
/// Averaging a wallpaper answers "what colour is it, roughly" and throws away
/// everything that made it worth looking at: a sunset averages to brown. A
/// palette keeps the colours that actually occupy the image, which is what
/// lets an adaptive gradient read as *derived from* the wallpaper rather than
/// smeared from it.
///
/// The derivation is deliberately pure and deterministic — it takes samples
/// and returns swatches — so it can be tested without a screen. Pixel reading
/// lives in ``CGImage/dominantColors(maximumCount:)``.
nonisolated struct WallpaperPalette: Equatable {
    /// One colour of a palette.
    struct Swatch: Equatable {
        /// Components in the 0...1 range.
        let red: Double
        let green: Double
        let blue: Double

        /// The fraction of the sampled image this swatch covers, 0...1.
        let weight: Double

        /// Perceived brightness, on the same W3C weighting the rest of the
        /// app uses to decide between light and dark menu bar items.
        var brightness: Double {
            ((red * 299) + (green * 587) + (blue * 114)) / 1000
        }

        /// The swatch as a color, in the given RGB color space.
        func cgColor(in colorSpace: CGColorSpace) -> CGColor? {
            CGColor(
                colorSpace: colorSpace,
                components: [CGFloat(red), CGFloat(green), CGFloat(blue), 1]
            )
        }

        /// Straight-line distance to another swatch in RGB.
        ///
        /// Not perceptually uniform, but the job here is only to reject
        /// near-duplicates, and RGB distance is predictable enough to write
        /// tests against.
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

    /// The swatches, most-covering first. May be empty.
    let swatches: [Swatch]

    /// The most-covering swatch, if any.
    var primary: Swatch? {
        swatches.first
    }

    /// The second most-covering swatch, falling back to ``primary`` so a
    /// single-colour wallpaper still yields a usable pair.
    var secondary: Swatch? {
        swatches.count > 1 ? swatches[1] : primary
    }

    /// How finely each channel is bucketed before counting.
    ///
    /// Five bits gives 32 levels per channel. Finer splits a smooth gradient
    /// into dozens of near-identical buckets and buries the actual subject;
    /// coarser merges colours a viewer would call different.
    private static let levelsPerChannel = 32

    /// Derives a palette from raw samples.
    ///
    /// Colours are bucketed and counted, then taken most-populous first,
    /// skipping any that sits too close to one already taken. Without that
    /// separation step a photo of the sky returns five blues, which makes a
    /// gradient look like a flat fill.
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

    /// Maps a sample onto its bucket.
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
