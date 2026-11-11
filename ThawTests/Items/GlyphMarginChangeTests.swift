//
//  GlyphMarginChangeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Pins how a picture retaken after the spacing shrank replaces the wider one:
/// GlyphMarginChange and its part in preferredCachedImage(existing:candidate:).
@MainActor
@Suite("Glyph margin change")
struct GlyphMarginChangeTests {
    /// A crop of the given point width, 16 points tall, with a band of opaque ink
    /// inkWidth wide centred in it and empty space either side. inkHeight centres a
    /// shorter band vertically; nil fills the full height.
    private static func capture(
        width: CGFloat,
        inkWidth: CGFloat,
        inkHeight: CGFloat? = nil,
        scale: CGFloat = 2
    ) throws -> MenuBarItemGlyphCapture {
        let pixelWidth = Int(width * scale)
        let pixelHeight = Int(16 * scale)
        let context = try #require(CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let inkPixels = Int(inkWidth * scale)
        let inkRows = inkHeight.map { Int($0 * scale) } ?? pixelHeight
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(
            x: (pixelWidth - inkPixels) / 2,
            y: (pixelHeight - inkRows) / 2,
            width: inkPixels,
            height: inkRows
        ))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: scale)
    }

    // MARK: onlyMarginsShrank

    @Test("The same icon with less space beside it counts as a margin change")
    func sameIconLessSpace() throws {
        let existing = try Self.capture(width: 36, inkWidth: 15)
        let candidate = try Self.capture(width: 22, inkWidth: 15)

        #expect(GlyphMarginChange.onlyMarginsShrank(from: existing, to: candidate))
    }

    @Test("Icons within a point of each other count as the same icon")
    func inkTolerance() throws {
        let existing = try Self.capture(width: 36, inkWidth: 15)

        #expect(try GlyphMarginChange.onlyMarginsShrank(from: existing, to: Self.capture(width: 22, inkWidth: 16)))
        #expect(try !GlyphMarginChange.onlyMarginsShrank(from: existing, to: Self.capture(width: 22, inkWidth: 17)))
    }

    @Test("A different icon is not a margin change")
    func differentIcon() throws {
        let existing = try Self.capture(width: 36, inkWidth: 15)

        #expect(try !GlyphMarginChange.onlyMarginsShrank(from: existing, to: Self.capture(width: 22, inkWidth: 10)))
        #expect(try !GlyphMarginChange.onlyMarginsShrank(
            from: existing,
            to: Self.capture(width: 22, inkWidth: 15, inkHeight: 10)
        ))
    }

    @Test("A picture that is not narrower is not a margin change")
    func notNarrower() throws {
        let existing = try Self.capture(width: 22, inkWidth: 15)

        #expect(try !GlyphMarginChange.onlyMarginsShrank(from: existing, to: Self.capture(width: 22, inkWidth: 15)))
        #expect(try !GlyphMarginChange.onlyMarginsShrank(from: existing, to: Self.capture(width: 36, inkWidth: 15)))
    }

    // MARK: preferredCachedImage

    @Test("A picture taken after the spacing shrank replaces the wider one")
    func narrowerSameIconWins() throws {
        // Rocket at spacing 16 was 36 pt wide; at spacing 2 it is 22 pt, under three quarters.
        let existing = try Self.capture(width: 36, inkWidth: 15)
        let candidate = try Self.capture(width: 22, inkWidth: 15)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: candidate) == candidate)
        #expect(MenuBarItemImageCache.preferredRevealedImage(existing: existing, candidate: candidate) == candidate)
    }

    @Test("A much narrower picture of another icon still loses")
    func narrowerOtherIconLoses() throws {
        let existing = try Self.capture(width: 36, inkWidth: 15)
        let candidate = try Self.capture(width: 22, inkWidth: 8)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: candidate) == existing)
    }

    @Test("A crop narrower than a trusted glyph loses even when its ink matches")
    func untrustedCropLoses() throws {
        let existing = try Self.capture(width: 24, inkWidth: 10)
        let candidate = try Self.capture(width: 14, inkWidth: 10)

        #expect(MenuBarItemImageCache.preferredCachedImage(existing: existing, candidate: candidate) == existing)
    }
}
