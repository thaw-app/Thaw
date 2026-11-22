//
//  NearUniformBackgroundKnockOutTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// The knock-out reads the background from the crop's edges. A glyph that touches a corner
/// must not poison that estimate, or the glyph is cleared and the bar fill is cached instead.
@Suite("Near-uniform background knock-out")
struct NearUniformBackgroundKnockOutTests {
    // MARK: - Image synthesis

    /// A background-filled image with a solid glyph rectangle, premultiplied-last as the knock-out reads it.
    private static func image(
        size: CGSize,
        background: (r: CGFloat, g: CGFloat, b: CGFloat),
        glyph: (r: CGFloat, g: CGFloat, b: CGFloat),
        glyphRect: CGRect
    ) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        let bgR = UInt8((background.r * 255).rounded())
        let bgG = UInt8((background.g * 255).rounded())
        let bgB = UInt8((background.b * 255).rounded())
        let glyphR = UInt8((glyph.r * 255).rounded())
        let glyphG = UInt8((glyph.g * 255).rounded())
        let glyphB = UInt8((glyph.b * 255).rounded())

        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = y * bytesPerRow + x * bytesPerPixel
                let inGlyph = glyphRect.contains(CGPoint(x: x, y: y))
                let (r, g, b) = inGlyph ? (glyphR, glyphG, glyphB) : (bgR, bgG, bgB)
                pixels[i] = r
                pixels[i + 1] = g
                pixels[i + 2] = b
                pixels[i + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            preconditionFailure("Test image synthesis failed")
        }
        return image
    }

    /// Whether the image has any fully-transparent pixel (alpha < 8).
    private static func hasTransparentPixel(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for i in stride(from: 3, to: pixels.count, by: bytesPerPixel) where pixels[i] < 8 {
            return true
        }
        return false
    }

    /// Whether an opaque pixel still matches the background, within tolerance.
    private static func retainsBackground(
        _ image: CGImage,
        background: (r: CGFloat, g: CGFloat, b: CGFloat),
        tolerance: UInt8 = 8
    ) -> Bool {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bgR = Int((background.r * 255).rounded())
        let bgG = Int((background.g * 255).rounded())
        let bgB = Int((background.b * 255).rounded())
        for i in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let a = Int(pixels[i + 3])
            guard a >= 8 else { continue }
            let r = Int(pixels[i]) * 255 / a
            let g = Int(pixels[i + 1]) * 255 / a
            let b = Int(pixels[i + 2]) * 255 / a
            if abs(r - bgR) <= tolerance, abs(g - bgG) <= tolerance, abs(b - bgB) <= tolerance {
                return true
            }
        }
        return false
    }

    // MARK: - Glyph touches the crop corner

    @Test("A glyph that nearly fills the frame (1px background border) survives, background cleared")
    func fullFrameGlyphSurvives() {
        // Every corner is glyph, as in a tight AX frame; only the 1px ring shows bar fill.
        let bg: (CGFloat, CGFloat, CGFloat) = (0.12, 0.12, 0.14)
        let glyph: (CGFloat, CGFloat, CGFloat) = (0.92, 0.32, 0.20)
        let image = Self.image(
            size: CGSize(width: 24, height: 24),
            background: bg,
            glyph: glyph,
            glyphRect: CGRect(x: 1, y: 1, width: 22, height: 22)
        )

        let knocked = image.knockingOutNearUniformBackground()

        #expect(knocked != nil)
        #expect(knocked.map { !Self.retainsBackground($0, background: bg) } ?? false)
    }

    @Test("A glyph that touches one corner still keeps the glyph and clears the background")
    func glyphTouchingOneCorner() {
        let bg: (CGFloat, CGFloat, CGFloat) = (0.10, 0.10, 0.12)
        let glyph: (CGFloat, CGFloat, CGFloat) = (0.95, 0.95, 0.95)
        let image = Self.image(
            size: CGSize(width: 24, height: 24),
            background: bg,
            glyph: glyph,
            glyphRect: CGRect(x: 0, y: 0, width: 12, height: 12)
        )

        let knocked = image.knockingOutNearUniformBackground()
        #expect(knocked != nil)
        #expect(knocked.map { !Self.retainsBackground($0, background: bg) } ?? false)
    }

    // MARK: - The plain case must keep working

    @Test("A centered glyph on a uniform background is preserved and background cleared")
    func centeredGlyph() {
        let bg: (CGFloat, CGFloat, CGFloat) = (0.15, 0.15, 0.17)
        let glyph: (CGFloat, CGFloat, CGFloat) = (0.20, 0.60, 0.95)
        let image = Self.image(
            size: CGSize(width: 24, height: 24),
            background: bg,
            glyph: glyph,
            glyphRect: CGRect(x: 4, y: 4, width: 16, height: 16)
        )

        let knocked = image.knockingOutNearUniformBackground()
        #expect(knocked != nil)
        #expect(knocked.map { !Self.retainsBackground($0, background: bg) } ?? false)
    }

    @Test("A slot that is only background returns nil (no glyph)")
    func emptySlotReturnsNil() {
        let bg: (CGFloat, CGFloat, CGFloat) = (0.13, 0.13, 0.15)
        let image = Self.image(
            size: CGSize(width: 24, height: 24),
            background: bg,
            glyph: bg, // no glyph
            glyphRect: CGRect(x: 0, y: 0, width: 0, height: 0)
        )

        let knocked = image.knockingOutNearUniformBackground()
        #expect(knocked == nil, "empty background crop should not produce a glyph image")
    }

    @Test("An image that is already transparent returns nil")
    func alreadyTransparentReturnsNil() {
        let width = 4, height = 4
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        guard let provider,
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            preconditionFailure("Test image synthesis failed")
        }

        let knocked = image.knockingOutNearUniformBackground()
        #expect(knocked == nil)
    }

    // MARK: - Edge-ring background estimate (the mode-over-corners decision)

    /// The pixels of image(size:background:glyph:glyphRect:), for the edge-ring estimate.
    private static func pixelBuffer(
        size: CGSize,
        background: (r: UInt8, g: UInt8, b: UInt8),
        glyph: (r: UInt8, g: UInt8, b: UInt8),
        glyphRect: CGRect
    ) -> (pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int) {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = y * bytesPerRow + x * bytesPerPixel
                let inGlyph = glyphRect.contains(CGPoint(x: x, y: y))
                let (r, g, b) = inGlyph ? glyph : background
                pixels[i] = r
                pixels[i + 1] = g
                pixels[i + 2] = b
                pixels[i + 3] = 255
            }
        }
        return (pixels, width, height, bytesPerRow)
    }

    @Test("Edge-ring estimate picks bar fill when a glyph only touches the corners")
    func estimateIgnoresGlyphTouchingCorners() {
        // Glyph in all four corners, bar fill along most of each edge: the edge pixels outvote the corners.
        let buf = Self.pixelBuffer(
            size: CGSize(width: 24, height: 24),
            background: (r: 30, g: 30, b: 36),
            glyph: (r: 220, g: 80, b: 50),
            glyphRect: CGRect(x: 0, y: 0, width: 6, height: 6)
        )
        var pixels = buf.pixels
        let stamp: [(x: Int, y: Int)] = [(18, 0), (0, 18), (18, 18)]
        for (sx, sy) in stamp {
            for y in sy ..< sy + 6 {
                for x in sx ..< sx + 6 {
                    let i = y * buf.bytesPerRow + x * 4
                    pixels[i] = 220
                    pixels[i + 1] = 80
                    pixels[i + 2] = 50
                    pixels[i + 3] = 255
                }
            }
        }
        guard let bg = CGImage.estimateEdgeRing(
            pixels: pixels,
            width: buf.width,
            height: buf.height,
            bytesPerRow: buf.bytesPerRow,
            bytesPerPixel: 4
        ).map({ (r: $0.r, g: $0.g, b: $0.b) }) else {
            Issue.record("edge-ring estimate returned nil for a bar-fill crop")
            return
        }
        #expect(abs(bg.r - 30) <= 8)
        #expect(abs(bg.g - 30) <= 8)
        #expect(abs(bg.b - 36) <= 8)
    }

    @Test("Edge-ring estimate returns nil for a fully transparent perimeter")
    func estimateReturnsNilForTransparentEdge() {
        let width = 8, height = 8, bytesPerPixel = 4, bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 2 ..< 6 {
            for x in 2 ..< 6 {
                let i = y * bytesPerRow + x * bytesPerPixel
                pixels[i] = 200
                pixels[i + 1] = 200
                pixels[i + 2] = 200
                pixels[i + 3] = 255
            }
        }
        let bg = CGImage.estimateEdgeRing(
            pixels: pixels,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            bytesPerPixel: bytesPerPixel
        ).map { (r: $0.r, g: $0.g, b: $0.b) }
        #expect(bg == nil)
    }

    // MARK: - Varying backgrounds (wallpaper gradients, busy patterns)

    /// Builds an RGBA image whose background is a horizontal gradient from
    /// from to to, with an optional solid glyph rect drawn on top.
    private static func gradientImage(
        size: CGSize,
        from: (r: CGFloat, g: CGFloat, b: CGFloat),
        to: (r: CGFloat, g: CGFloat, b: CGFloat),
        glyph: (r: CGFloat, g: CGFloat, b: CGFloat)? = nil,
        glyphRect: CGRect = .zero
    ) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = y * bytesPerRow + x * bytesPerPixel
                let t = width > 1 ? CGFloat(x) / CGFloat(width - 1) : 0
                var r = from.r + (to.r - from.r) * t
                var g = from.g + (to.g - from.g) * t
                var b = from.b + (to.b - from.b) * t
                if let glyph, glyphRect.contains(CGPoint(x: x, y: y)) {
                    r = glyph.r
                    g = glyph.g
                    b = glyph.b
                }
                pixels[i] = UInt8((r * 255).rounded())
                pixels[i + 1] = UInt8((g * 255).rounded())
                pixels[i + 2] = UInt8((b * 255).rounded())
                pixels[i + 3] = 255
            }
        }
        return makeImage(pixels: pixels, width: width, height: height)
    }

    /// Builds an RGBA image whose background is deterministic per-pixel noise,
    /// a stand-in for a busy wallpaper, where no colour dominates the edge ring.
    private static func noisyImage(size: CGSize, glyphRect: CGRect) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        var seed: UInt32 = 0x9E37_79B9
        func next() -> UInt8 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return UInt8((seed >> 16) & 0xFF)
        }
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = y * bytesPerRow + x * bytesPerPixel
                if glyphRect.contains(CGPoint(x: x, y: y)) {
                    pixels[i] = 255
                    pixels[i + 1] = 0
                    pixels[i + 2] = 0
                } else {
                    pixels[i] = next()
                    pixels[i + 1] = next()
                    pixels[i + 2] = next()
                }
                pixels[i + 3] = 255
            }
        }
        return makeImage(pixels: pixels, width: width, height: height)
    }

    private static func makeImage(pixels: [UInt8], width: Int, height: Int) -> CGImage {
        let bytesPerRow = width * 4
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            preconditionFailure("Test image synthesis failed")
        }
        return image
    }

    /// One background colour would keep the rest of the gradient as glyph, so the model is local.
    @Test("A gradient background is cleared, not cached as the glyph")
    func gradientBackgroundIsCleared() {
        let image = Self.gradientImage(
            size: CGSize(width: 48, height: 24),
            from: (r: 0.16, g: 0.16, b: 0.16),
            to: (r: 0.78, g: 0.78, b: 0.78),
            glyph: (r: 1, g: 0, b: 0),
            glyphRect: CGRect(x: 20, y: 8, width: 8, height: 8)
        )

        guard let knocked = image.knockingOutNearUniformBackground() else {
            Issue.record("gradient crop was rejected outright; the local model should have read it")
            return
        }
        #expect(
            Self.retainsBackground(knocked, background: (r: 0.16, g: 0.16, b: 0.16), tolerance: 40) == false,
            "the dark end of the gradient survived as glyph"
        )
        #expect(
            Self.retainsBackground(knocked, background: (r: 0.78, g: 0.78, b: 0.78), tolerance: 40) == false,
            "the light end of the gradient survived as glyph"
        )
        #expect(
            Self.retainsBackground(knocked, background: (r: 1, g: 0, b: 0)),
            "the glyph itself was cleared"
        )
    }

    /// With no dominant colour on the ring, the caller falls back to the app icon.
    @Test("A busy background is rejected rather than cached")
    func busyBackgroundIsRejected() {
        let image = Self.noisyImage(
            size: CGSize(width: 48, height: 24),
            glyphRect: CGRect(x: 20, y: 8, width: 8, height: 8)
        )

        #expect(
            image.knockingOutNearUniformBackground() == nil,
            "a busy background was accepted as an item glyph"
        )
    }

    /// Builds an RGBA image of a smooth multi-hue field with scattered
    /// hue-shifted patches on top, a blurred photographic wallpaper where the
    /// colour model follows the field but cannot follow the patches.
    private static func patchworkImage(size: CGSize, glyphRect: CGRect) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        /// Low amplitude on purpose, so the background model follows it as it follows a soft wallpaper.
        func field(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
            let fx = Double(x), fy = Double(y)
            return (
                r: 150 + 22 * sin(fx / 9) * cos(fy / 7),
                g: 140 + 20 * cos(fx / 11) * sin(fy / 8),
                b: 128 + 18 * sin((fx + fy) / 13)
            )
        }
        // Small patches of another hue, which the model cannot follow.
        var patches = Set<Int>()
        for (px, py) in [(3, 2), (12, 4), (34, 3), (43, 9), (6, 17), (25, 19), (39, 18), (17, 21)] {
            for dy in 0 ..< 2 {
                for dx in 0 ..< 2 {
                    patches.insert((py + dy) * width + (px + dx))
                }
            }
        }

        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = y * bytesPerRow + x * bytesPerPixel
                var colour = field(x: x, y: y)
                if patches.contains(y * width + x) {
                    colour = (r: colour.r + 90, g: colour.g - 70, b: colour.b + 60)
                }
                let inGlyph = glyphRect.contains(CGPoint(x: x, y: y))
                pixels[i] = UInt8(min(255, max(0, inGlyph ? 255 : colour.r)).rounded())
                pixels[i + 1] = UInt8(min(255, max(0, inGlyph ? 255 : colour.g)).rounded())
                pixels[i + 2] = UInt8(min(255, max(0, inGlyph ? 255 : colour.b)).rounded())
                pixels[i + 3] = 255
            }
        }
        return makeImage(pixels: pixels, width: width, height: height)
    }

    /// Shipped once: islands of a photographic wallpaper survived beside the glyph and were cached as the icon.
    @Test("Blurred wallpaper patches behind a glyph are rejected")
    func blurredWallpaperIsRejected() {
        let image = Self.patchworkImage(
            size: CGSize(width: 48, height: 24),
            glyphRect: CGRect(x: 20, y: 8, width: 8, height: 8)
        )

        #expect(
            image.knockingOutNearUniformBackground() == nil,
            "wallpaper patches were accepted as the item's glyph"
        )
    }

    /// A solid bar (Reduce Transparency) makes every crop opaque.
    @Test("A many-part glyph on a solid bar fill survives")
    func manyPartGlyphOnSolidFillSurvives() {
        let width = 48
        let height = 48
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = (y * width + x) * 4
                // A 3×3 grid of 6px dots on a dark solid fill.
                let inDot = (x - 9) % 12 < 6 && (y - 9) % 12 < 6 && x >= 9 && y >= 9 && x < 39 && y < 39
                let value: UInt8 = inDot ? 240 : 31
                pixels[i] = value
                pixels[i + 1] = value
                pixels[i + 2] = value
                pixels[i + 3] = 255
            }
        }
        let image = Self.makeImage(pixels: pixels, width: width, height: height)

        #expect(image.glyphPresenceOverNearUniformBackground() == .present)
        let knocked = image.knockingOutNearUniformBackground()
        #expect(knocked != nil)
        #expect(knocked.map { Self.hasTransparentPixel($0) } ?? false)
    }

    /// A white app tile filling most of the frame, on a bar whose blue drifts
    /// across colour buckets. The tile is the icon, not the background.
    @Test("A full-bleed white tile on a graded bar keeps its white")
    func fullBleedTileOnGradedBarKeepsWhite() throws {
        let width = 42
        let height = 48
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = (y * width + x) * 4
                let inTile = x >= 5 && x < 37 && y >= 6 && y < 42
                let inMark = x >= 14 && x < 28 && y >= 14 && y < 34
                let rgb: (UInt8, UInt8, UInt8) = if inMark {
                    (20, 24, 60)
                } else if inTile {
                    (250, 250, 250)
                } else {
                    (12, UInt8(90 + x / 3), 160)
                }
                pixels[i] = rgb.0
                pixels[i + 1] = rgb.1
                pixels[i + 2] = rgb.2
                pixels[i + 3] = 255
            }
        }
        let image = Self.makeImage(pixels: pixels, width: width, height: height)

        let knocked = try #require(image.knockingOutNearUniformBackground())
        #expect(Self.retainsBackground(knocked, background: (250 / 255, 250 / 255, 250 / 255)))
        #expect(Self.hasTransparentPixel(knocked))
    }
}
