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

/// Pins CGImage.knockingOutNearUniformBackground(), the display-strip
/// background knock-out that keeps a status-item glyph and clears the menu bar
/// fill it was cut from.
///
/// The knock-out estimates the background color from the crop's edges. A
/// glyph that fills its AX frame and touches a crop corner (a full-frame icon)
/// can poison a corner-sampled estimate, so the knock-out clears the glyph and
/// the bar fill bleeds into the cached icon. These tests build synthetic crops
/// (uniform background plus a full-frame glyph) and assert the glyph survives
/// and the background is cleared.
@Suite("Near-uniform background knock-out")
struct NearUniformBackgroundKnockOutTests {
    // MARK: - Image synthesis

    /// Builds an RGBA image of size filled with background, then draws a
    /// solid glyph rectangle covering the given pixel rect on top of it.
    /// Premultiplied-last (RGBA) byte order to match the knock-out's reader.
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

    /// Whether the image still holds an opaque pixel whose color matches the
    /// given background (within a small tolerance), i.e. background was NOT
    /// fully knocked out.
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
        // A 24x24 crop with a dark bar fill and a bright glyph that fills all
        // but a 1px border, realistic for a tight AX frame whose glyph touches
        // the corners. Every corner is a glyph pixel, which poisons a
        // corner-sample estimate. The 1px edge ring still exposes enough bar
        // fill for an edge-aware estimate to pick it.
        let bg: (CGFloat, CGFloat, CGFloat) = (0.12, 0.12, 0.14)
        let glyph: (CGFloat, CGFloat, CGFloat) = (0.92, 0.32, 0.20)
        let image = Self.image(
            size: CGSize(width: 24, height: 24),
            background: bg,
            glyph: glyph,
            glyphRect: CGRect(x: 1, y: 1, width: 22, height: 22)
        )

        let knocked = image.knockingOutNearUniformBackground()

        // The glyph must survive.
        #expect(knocked != nil, "glyph was knocked out entirely")
        // The bar fill must be cleared from the 1px border, not retained as a
        // bleed into the cached icon.
        #expect(knocked.map { !Self.retainsBackground($0, background: bg) } ?? false,
                "bar fill was retained (background bled into the glyph)")
    }

    @Test("A glyph that touches one corner still keeps the glyph and clears the background")
    func glyphTouchingOneCorner() {
        // Glyph covering the top-left corner only, on a uniform background
        // everywhere else. A corner sample would read the glyph at the
        // top-left and skew the average; the edge-aware estimate must still
        // pick the bar fill from the other three edges.
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
        // Fully-transparent 4x4 image.
        let width = 4, height = 4
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        // all zero => fully transparent already
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

    /// Builds an RGBA pixel buffer of the given size filled with background,
    /// with a solid glyph rectangle drawn on top, premultiplied-last.
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
        // 24x24 bar-fill crop with a glyph that touches all four corners but
        // leaves bar fill along most of each edge, the real-world shape of a
        // full-frame icon. The bar-fill edge pixels (the majority of the
        // ring) outvote the glyph's corner pixels in the mode, so the estimate
        // is bar fill, where a corner sample would read glyph at all four.
        let buf = Self.pixelBuffer(
            size: CGSize(width: 24, height: 24),
            background: (r: 30, g: 30, b: 36),
            glyph: (r: 220, g: 80, b: 50),
            glyphRect: CGRect(x: 0, y: 0, width: 6, height: 6)
        )
        // Add the other three corner glyphs so all four corners are glyph.
        // (pixelBuffer draws one rect; stamp the other three by re-filling.)
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
        // The estimate must be the bar fill, not the glyph color.
        #expect(abs(bg.r - 30) <= 8)
        #expect(abs(bg.g - 30) <= 8)
        #expect(abs(bg.b - 36) <= 8)
    }

    @Test("Edge-ring estimate returns nil for a fully transparent perimeter")
    func estimateReturnsNilForTransparentEdge() {
        // All edge pixels transparent (alpha 0); interior opaque. There is no
        // background to read on the ring.
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

    /// With one modelled background colour, everything in a wallpaper
    /// gradient away from that band survives as "glyph" and the cached icon is
    /// the wallpaper. The local model has to clear all of it and keep only
    /// the glyph.
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

    /// When the ring has no dominant colour there is no background to model,
    /// and the honest answer is a rejection: the caller falls back to the app
    /// icon instead of caching a crop of the wallpaper.
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

        /// Smooth field: low amplitude on purpose, so the per-pixel background
        /// model follows it and clears it, exactly as it clears a soft wallpaper.
        func field(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
            let fx = Double(x), fy = Double(y)
            return (
                r: 150 + 22 * sin(fx / 9) * cos(fy / 7),
                g: 140 + 20 * cos(fx / 11) * sin(fy / 8),
                b: 128 + 18 * sin((fx + fy) / 13)
            )
        }
        // Scattered patches the model cannot follow: distinct hue, small,
        // separated, the foliage islands seen beside real glyphs.
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

    /// Blurred multi-hue patches, a photographic wallpaper, are the case that
    /// actually shipped: the local model cleared most of it, but islands of the
    /// wallpaper survived beside the glyph and were cached as the icon.
    /// Scattered survivors are not a glyph, so this must be rejected.
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
