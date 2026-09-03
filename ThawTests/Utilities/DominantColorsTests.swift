//
//  DominantColorsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Exercises ``CGImage.dominantColors(maximumCount:alphaThreshold:)`` —
/// the pixel-sampling front end of the Adaptive Gradient tint — against
/// synthetic images with known pixel layouts.
@Suite("Dominant color extraction")
struct DominantColorsTests {
    // MARK: - Single color

    @Test("A solid image yields one swatch of that color")
    func solidImageYieldsOneSwatch() throws {
        let image = try makeCanvas(width: 16, height: 16) { context in
            context.setFillColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }

        let palette = image.dominantColors()

        #expect(palette.swatches.count == 1)
        guard let swatch = palette.swatches.first else { return }
        #expect(abs(swatch.red - 0.8) < 0.02)
        #expect(abs(swatch.green - 0.2) < 0.02)
        #expect(abs(swatch.blue - 0.1) < 0.02)
    }

    // MARK: - Coverage ordering

    @Test("A two-color split yields both colors, most-covering first")
    func splitImageOrdersByCoverage() throws {
        let image = try makeCanvas(width: 16, height: 16) { context in
            // 3/4 of the canvas green, 1/4 red.
            context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 12, width: 16, height: 4))
        }

        let palette = image.dominantColors()
        #expect(palette.swatches.count == 2)
        guard palette.swatches.count == 2 else { return }
        #expect(palette.swatches[0].green > 0.9)
        #expect(palette.swatches[1].red > 0.9)
        #expect(palette.swatches[0].weight >= palette.swatches[1].weight)
    }

    @Test("maximumCount caps the number of swatches")
    func maximumCountCapsSwatches() throws {
        let image = try makeCanvas(width: 8, height: 8) { context in
            for (index, color) in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 1.0, 0.0)]
                .enumerated()
            {
                context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
                context.fill(CGRect(x: index * 2, y: 0, width: 2, height: 8))
            }
        }

        let palette = image.dominantColors(maximumCount: 2)
        #expect(palette.swatches.count == 2)
    }

    // MARK: - Alpha handling

    @Test("Pixels below the alpha threshold are excluded")
    func alphaThresholdFiltersPixels() throws {
        let image = try makeCanvas(width: 8, height: 8) { context in
            // Half the canvas is fully transparent black, half opaque red.
            context.clear(CGRect(x: 0, y: 0, width: 8, height: 4))
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 4, width: 8, height: 4))
        }

        let palette = image.dominantColors()
        #expect(palette.swatches.count == 1)
        guard let swatch = palette.swatches.first else { return }
        #expect(swatch.red > 0.9)
    }

    @Test("A fully transparent image yields an empty palette")
    func transparentImageYieldsEmptyPalette() throws {
        let image = try makeCanvas(width: 8, height: 8) { context in
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        let palette = image.dominantColors(alphaThreshold: 0.5)
        #expect(palette.swatches.isEmpty)
    }

    @Test("An out-of-range alpha threshold is clamped, not fatal")
    func alphaThresholdClamps() throws {
        let image = try makeOpaqueImage(width: 4, height: 4)

        // -1 clamps to 0 (every pixel counts); 2 clamps to 1 (only fully
        // opaque pixels survive) — an opaque image renders for both.
        let low = image.dominantColors(alphaThreshold: -1)
        let high = image.dominantColors(alphaThreshold: 2)

        #expect(!low.swatches.isEmpty)
        #expect(!high.swatches.isEmpty)
    }

    // MARK: - Color spaces

    @Test("A non-RGB image still renders through a fallback color space")
    func nonRGBImageRenders() throws {
        let context = try #require(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.setFillColor(gray: 1.0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())

        let palette = image.dominantColors()
        #expect(!palette.swatches.isEmpty)
    }
}
