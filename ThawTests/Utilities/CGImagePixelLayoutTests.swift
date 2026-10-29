//
//  CGImagePixelLayoutTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Transparency and dominant colours read from raw 4x4 images, built byte by byte so each
/// alpha position and byte order is exercised.
@Suite("CGImage pixel layouts")
struct CGImagePixelLayoutTests {
    private static let side = 4

    /// A 4x4 image whose pixels are all background, except one pixel set to mark.
    private static func image(
        alphaInfo: CGImageAlphaInfo,
        byteOrder: CGBitmapInfo,
        background: [UInt8] = [0, 0, 0, 0],
        mark: [UInt8]? = nil,
        bitsPerComponent: Int = 8
    ) throws -> CGImage {
        let bytesPerPixel = 4 * bitsPerComponent / 8
        var bytes = [UInt8]()
        for index in 0 ..< side * side {
            let pixel = index == 5 ? (mark ?? background) : background
            for component in pixel {
                bytes.append(component)
                if bitsPerComponent == 16 {
                    bytes.append(component)
                }
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(
            width: side,
            height: side,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bytesPerPixel * 8,
            bytesPerRow: side * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue).union(byteOrder),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    @Test(
        "The fast path reads alpha from the byte each layout stores it in",
        arguments: [
            (CGImageAlphaInfo.premultipliedFirst, CGBitmapInfo.byteOrder32Little, 3),
            (.first, .byteOrder32Little, 3),
            (.premultipliedLast, .byteOrder32Little, 0),
            (.last, .byteOrder32Little, 0),
            (.premultipliedFirst, .byteOrder32Big, 0),
            (.first, .byteOrder32Big, 0),
            (.premultipliedLast, .byteOrder32Big, 3),
            (.last, .byteOrder32Big, 3),
        ]
    )
    func alphaByte(alphaInfo: CGImageAlphaInfo, byteOrder: CGBitmapInfo, alphaIndex: Int) throws {
        var opaque: [UInt8] = [0, 0, 0, 0]
        opaque[alphaIndex] = 255
        // A colour byte at full value in every other slot must not read as alpha.
        var colourOnly: [UInt8] = [255, 255, 255, 255]
        colourOnly[alphaIndex] = 0

        let clear = try Self.image(alphaInfo: alphaInfo, byteOrder: byteOrder)
        let marked = try Self.image(alphaInfo: alphaInfo, byteOrder: byteOrder, mark: opaque)
        let tinted = try Self.image(alphaInfo: alphaInfo, byteOrder: byteOrder, background: colourOnly)

        #expect(clear.isTransparent())
        #expect(!marked.isTransparent())
        #expect(tinted.isTransparent(), "colour without alpha is still see-through")
    }

    @Test("A faint pixel counts as clear only up to the threshold")
    func threshold() throws {
        let faint = try Self.image(alphaInfo: .premultipliedFirst, byteOrder: .byteOrder32Little, mark: [10, 10, 10, 40])
        #expect(!faint.isTransparent())
        #expect(faint.isTransparent(alphaThreshold: 0.5))
        #expect(!faint.isTransparent(alphaThreshold: 1), "a threshold of one leaves nothing transparent")
    }

    @Test("Layouts the fast path doesn't know fall back to the slow scan with the same answer")
    func slowFallbacks() throws {
        let defaultOrder = try Self.image(alphaInfo: .premultipliedLast, byteOrder: [], mark: [0, 0, 0, 255])
        let defaultOrderClear = try Self.image(alphaInfo: .premultipliedLast, byteOrder: [])
        let wide = try Self.image(alphaInfo: .premultipliedLast, byteOrder: .byteOrder16Little, mark: [0, 0, 0, 255], bitsPerComponent: 16)
        let opaqueNoAlpha = try Self.image(alphaInfo: .noneSkipLast, byteOrder: .byteOrder32Big)

        #expect(!defaultOrder.isTransparent())
        #expect(defaultOrderClear.isTransparent())
        #expect(!wide.isTransparent())
        #expect(!opaqueNoAlpha.isTransparent(), "an image without alpha is opaque")
    }

    @Test("Dominant colours come from the opaque pixels, most covering first")
    func dominantColors() throws {
        var bytes = [UInt8]()
        for index in 0 ..< Self.side * Self.side {
            // Big-endian RGBA: twelve red pixels, four blue.
            bytes += index < 12 ? [255, 0, 0, 255] : [0, 0, 255, 255]
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(
            width: Self.side,
            height: Self.side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: Self.side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))

        let palette = image.dominantColors()
        let primary = try #require(palette.swatches.first)
        #expect(primary.red > 0.8 && primary.blue < 0.2)
        #expect(palette.swatches.contains { $0.blue > 0.8 && $0.red < 0.2 })
        #expect(primary.weight > 0.5, "red covers three quarters of the image")

        let clear = try Self.image(alphaInfo: .premultipliedLast, byteOrder: .byteOrder32Big)
        #expect(clear.dominantColors().swatches.isEmpty, "fully transparent pixels give no colour")
    }
}
