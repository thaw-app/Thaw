//
//  WallpaperPalette.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Dominant colors preserve wallpaper detail that averaging loses, such as a sunset averaging to brown.
/// Derivation is pure and deterministic; pixel reading lives in CGImage.dominantColors(maximumCount:).
nonisolated struct WallpaperPalette: Equatable {
    struct Swatch: Equatable {
        /// Components in the 0...1 range.
        let red: Double
        let green: Double
        let blue: Double

        /// The fraction of the sampled image this swatch covers, 0...1.
        let weight: Double

        /// Uses the app's W3C weighting for light/dark menu bar item selection.
        var brightness: Double {
            ((red * 299) + (green * 587) + (blue * 114)) / 1000
        }

        func cgColor(in colorSpace: CGColorSpace) -> CGColor? {
            CGColor(
                colorSpace: colorSpace,
                components: [CGFloat(red), CGFloat(green), CGFloat(blue), 1]
            )
        }

        /// RGB distance is not perceptually uniform, but suffices for predictable near-duplicate rejection.
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

    var primary: Swatch? {
        swatches.first
    }

    /// Falls back to primary so single-color wallpapers still yield a usable pair.
    var secondary: Swatch? {
        swatches.count > 1 ? swatches[1] : primary
    }

    /// Finer than 32 levels fragments gradients; coarser merges visibly different colors.
    private static let levelsPerChannel = 32

    /// Select the most populous buckets, separated to avoid near-identical colors producing a flat gradient.
    ///
    /// - Parameters:
    ///   - samples: The observed pixels. Order does not matter.
    ///   - maximumCount: The most swatches to return.
    ///   - minimumSeparation: RGB distance between swatches. Zero returns raw most-populous buckets.
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
        // Break population ties by bucket key for deterministic results.
        let ranked = counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }

        var result: [Swatch] = []
        for (key, count) in ranked {
            guard result.count < maximumCount else { break }
            guard let total = totals[key] else { continue }
            // Average sampled colors instead of substituting the bucket center.
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
