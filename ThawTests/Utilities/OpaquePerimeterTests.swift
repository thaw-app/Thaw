//
//  OpaquePerimeterTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// SkyLight returns opaque slabs for uncomposited windows, which transparency checks mistake for content.
/// Check the perimeter first to distinguish native alpha from a slab needing strip-crop analysis.
struct OpaquePerimeterTests {
    @Test("a solid opaque black square has an opaque perimeter and no glyph")
    func opaqueBlackSlab() throws {
        let image = try Self.rgba(width: 24, height: 24) { _, _ in (0, 0, 0, 255) }
        #expect(image.hasOpaquePerimeter())
        #expect(image.glyphPresenceOverNearUniformBackground() == .absent)
    }

    @Test("an opaque black window with a white glyph is knocked out, not dropped")
    func opaqueBlackWithGlyph() throws {
        let image = try Self.rgba(width: 24, height: 24) { x, y in
            (6 ... 17).contains(x) && (6 ... 17).contains(y) ? (255, 255, 255, 255) : (0, 0, 0, 255)
        }
        #expect(image.hasOpaquePerimeter())
        #expect(image.glyphPresenceOverNearUniformBackground() == .present)
        #expect(image.knockingOutNearUniformBackground() != nil)
    }

    @Test("a window's own transparent background is not an opaque perimeter")
    func transparentBackground() throws {
        let image = try Self.rgba(width: 24, height: 24) { x, y in
            (6 ... 17).contains(x) && (6 ... 17).contains(y) ? (255, 255, 255, 255) : (0, 0, 0, 0)
        }
        #expect(!image.hasOpaquePerimeter())
        #expect(!image.isTransparent())
    }

    @Test("a glyph whose anti-aliased edge touches the ring does not flip a transparent ring")
    func glyphTouchingRing() throws {
        let image = try Self.rgba(width: 24, height: 24) { x, y in
            y == 0 && (8 ... 15).contains(x) ? (255, 255, 255, 255) : (0, 0, 0, 0)
        }
        #expect(!image.hasOpaquePerimeter())
    }

    @Test("an image with no alpha channel is treated as opaque")
    func noAlphaChannel() throws {
        let width = 16
        let height = 16
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        #expect(!image.isTransparent())
        #expect(image.hasOpaquePerimeter())
    }

    // MARK: - Fixture

    private static func rgba(
        width: Int,
        height: Int,
        pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
    ) throws -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let (r, g, b, a) = pixel(x, y)
                let i = y * bytesPerRow + x * 4
                pixels[i] = r
                pixels[i + 1] = g
                pixels[i + 2] = b
                pixels[i + 3] = a
            }
        }
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }
}
