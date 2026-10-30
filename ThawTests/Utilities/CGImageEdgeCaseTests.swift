//
//  CGImageEdgeCaseTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// The image helpers' less travelled branches, on bitmaps built pixel by pixel.
@MainActor
@Suite("Image processing edge cases")
struct CGImageEdgeCaseTests {
    private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    /// Builds an image from a closure over (x, y), with y = 0 the top row. Colours are straight, not premultiplied.
    private static func image(
        width: Int,
        height: Int,
        bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue,
        pixel: (Int, Int) -> RGBA
    ) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let p = pixel(x, y)
                let i = (y * width + x) * 4
                let a = Int(p.a)
                bytes[i] = UInt8(Int(p.r) * a / 255)
                bytes[i + 1] = UInt8(Int(p.g) * a / 255)
                bytes[i + 2] = UInt8(Int(p.b) * a / 255)
                bytes[i + 3] = p.a
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private static func solid(width: Int, height: Int, _ colour: RGBA) -> CGImage {
        image(width: width, height: height) { _, _ in colour }
    }

    @Test("Pixels below the alpha threshold are left out of the average colour")
    func faintPixelsAreSkipped() throws {
        let image = Self.image(width: 10, height: 10) { x, _ in x < 5 ? (255, 0, 0, 255) : (0, 0, 255, 20) }
        let colour = try #require(image.averageColor())
        let components = try #require(colour.components)
        #expect(components[0] > 0.95)
        #expect(components[2] < 0.05)
        #expect(components[3] > 0.95)
    }

    @Test("An image with every pixel below the alpha threshold has no average colour")
    func transparentImageHasNoAverage() {
        #expect(Self.solid(width: 10, height: 10, (255, 255, 255, 10)).averageColor() == nil)
    }

    @Test("An image in the default byte order reports its transparency correctly")
    func defaultByteOrderTransparency() {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let clear = Self.image(width: 6, height: 6, bitmapInfo: info) { _, _ in (0, 0, 0, 0) }
        let dot = Self.image(width: 6, height: 6, bitmapInfo: info) { x, y in x == 3 && y == 2 ? (0, 0, 0, 255) : (0, 0, 0, 0) }
        #expect(clear.isTransparent())
        #expect(!dot.isTransparent())
        #expect(dot.isTransparent(alphaThreshold: 0.99) == false)
    }

    @Test("An opaque tile or an empty crop is not a single-ink glyph")
    func singleInkRejectsTilesAndEmptyCrops() {
        #expect(!Self.solid(width: 12, height: 12, (90, 90, 90, 255)).isSingleInkGlyph())
        #expect(!Self.solid(width: 12, height: 12, (0, 0, 0, 0)).isSingleInkGlyph())
        let glyph = Self.image(width: 12, height: 12) { x, _ in (4 ..< 8).contains(x) ? (40, 40, 40, 255) : (0, 0, 0, 0) }
        #expect(glyph.isSingleInkGlyph())
    }

    @Test("Trimming the top edge drops the transparent rows above the content")
    func trimTopEdge() throws {
        let image = Self.image(width: 8, height: 10) { _, y in y >= 3 ? (0, 0, 0, 255) : (0, 0, 0, 0) }
        let trimmed = try #require(image.trimmingTransparency(around: [.minYEdge]))
        #expect(trimmed.width == 8)
        #expect(trimmed.height == 7)
        let topAlpha = trimmed.withPremultipliedRGBA8 { bytes, _ in bytes[3] }
        #expect(topAlpha == 255, "the crop starts at the first opaque row")
    }

    @Test("A threshold no pixel can pass leaves the image as it is")
    func trimWithImpossibleThreshold() {
        let image = Self.image(width: 6, height: 6) { x, _ in x < 2 ? (0, 0, 0, 0) : (0, 0, 0, 255) }
        #expect(image.trimmingTransparency(alphaThreshold: 1) === image)
        #expect(image.trimmingTransparency()?.width == 4)
    }

    @Test("A crop too small to have an edge ring, or a zero distance, cannot be separated")
    func tooSmallToSeparate() {
        let tiny = Self.solid(width: 2, height: 2, (0, 0, 0, 255))
        #expect(tiny.separatedFromNearUniformBackground().presence == .indeterminate)
        let image = Self.solid(width: 10, height: 10, (0, 0, 0, 255))
        #expect(image.separatedFromNearUniformBackground(maxColorDistance: 0).presence == .indeterminate)
    }

    @Test("Transparent pixels inside a crop are cleared with the background")
    func transparentPixelsAreCleared() throws {
        let image = Self.image(width: 30, height: 20) { x, y in
            if (13 ..< 17).contains(x), (3 ..< 17).contains(y) {
                return (0, 0, 0, 255)
            }
            if (2 ..< 5).contains(x), (8 ..< 11).contains(y) {
                return (0, 0, 0, 0)
            }
            return (200, 200, 200, 255)
        }
        let separated = image.separatedFromNearUniformBackground()
        #expect(separated.presence == .present)
        let output = try #require(separated.image)
        let alpha = try #require(output.withPremultipliedRGBA8 { bytes, bytesPerRow in
            (hole: bytes[9 * bytesPerRow + 3 * 4 + 3], glyph: bytes[10 * bytesPerRow + 15 * 4 + 3])
        })
        #expect(alpha.hole == 0)
        #expect(alpha.glyph == 255)
    }

    @Test("A frame whose outer ring is wallpaper is separated inside the ring that agrees on one fill")
    func separatesInsideAnAgreeingRing() throws {
        var seed: UInt32 = 12345
        func noise() -> UInt8 {
            seed = seed &* 1_103_515_245 &+ 12345
            return UInt8(truncatingIfNeeded: seed >> 16)
        }
        let image = Self.image(width: 36, height: 24) { x, y in
            if x < 2 || y < 2 || x >= 34 || y >= 22 {
                return (noise(), noise(), noise(), 255)
            }
            if (16 ..< 20).contains(x), (5 ..< 19).contains(y) {
                return (0, 0, 0, 255)
            }
            return (128, 128, 128, 255)
        }
        let separated = image.separatedFromNearUniformBackground()
        #expect(separated.presence == .present)
        let output = try #require(separated.image)
        #expect(output.width == 32)
        #expect(output.height == 20)
    }

    @Test("Many shapes read as ink only when they are of some size and stand far from the background")
    func looksLikeInk() {
        let far = Array(repeating: CGFloat(120), count: 100)
        let near = Array(repeating: CGFloat(10), count: 100)
        #expect(CGImage.looksLikeInk(componentSizes: [50, 50], kept: 100, keptDistances: far, maxColorDistance: 36, imageArea: 1000))
        #expect(!CGImage.looksLikeInk(componentSizes: [50, 50], kept: 100, keptDistances: near, maxColorDistance: 36, imageArea: 1000))
        #expect(!CGImage.looksLikeInk(componentSizes: Array(repeating: 2, count: 50), kept: 100, keptDistances: far, maxColorDistance: 36, imageArea: 1000))
        #expect(!CGImage.looksLikeInk(componentSizes: [], kept: 0, keptDistances: [], maxColorDistance: 36, imageArea: 1000))
    }
}
