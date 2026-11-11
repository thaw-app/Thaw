//
//  GlyphLeadingCutTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// A picture taken while the icon still slides in keeps its right edge and loses its left part.
/// The reveal path keeps the complete picture it has, and a complete one replaces a cut one it
/// kept. Live recaptures take what the item really draws, even when that loses its left part.
@MainActor
@Suite("Glyph leading cut")
struct GlyphLeadingCutTests {
    private typealias Cache = MenuBarItemImageCache

    /// A 16 pt tall crop, with ink from inkFrom to inkTo points across its width.
    private static func crop(
        width: CGFloat, inkFrom: CGFloat, inkTo: CGFloat, scale: CGFloat = 2, alpha: CGFloat = 1
    ) throws -> MenuBarItemGlyphCapture {
        let pixelWidth = Int(width * scale), pixelHeight = Int(16 * scale)
        let context = try #require(CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: alpha))
        context.fill(CGRect(x: inkFrom * scale, y: 0, width: (inkTo - inkFrom) * scale, height: CGFloat(pixelHeight)))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: scale)
    }

    @Test("A reveal catch missing its left part loses to the complete one")
    func leftCutLosesOnReveal() throws {
        let complete = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let cut = try Self.crop(width: 24, inkFrom: 12, inkTo: 20)
        #expect(Cache.preferredRevealedImage(existing: complete, candidate: cut) == complete)
    }

    @Test("A live item whose left ink disappears updates, as right-aligned text getting shorter")
    func leftCutWinsLive() throws {
        let complete = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let cut = try Self.crop(width: 24, inkFrom: 12, inkTo: 20)
        #expect(Cache.preferredCachedImage(existing: complete, candidate: cut) == cut)
    }

    @Test("A reveal catch that is a sliver of the icon loses to the complete one")
    func sliverLosesOnReveal() throws {
        let complete = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let sliver = try Self.crop(width: 24, inkFrom: 18, inkTo: 20)
        #expect(Cache.preferredRevealedImage(existing: complete, candidate: sliver) == complete)
    }

    @Test("A complete picture replaces a cut one already kept")
    func completeReplacesCut() throws {
        let cut = try Self.crop(width: 24, inkFrom: 12, inkTo: 20)
        let complete = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        #expect(Cache.preferredCachedImage(existing: cut, candidate: complete) == complete)
        #expect(Cache.preferredRevealedImage(existing: cut, candidate: complete) == complete)
    }

    @Test("Text that gets shorter and a narrower centred symbol still replace the old picture")
    func realNarrowingWins() throws {
        let wide = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let shorterText = try Self.crop(width: 24, inkFrom: 4, inkTo: 12)
        let narrowerSymbol = try Self.crop(width: 24, inkFrom: 8, inkTo: 16)
        #expect(Cache.preferredCachedImage(existing: wide, candidate: shorterText) == shorterText)
        #expect(Cache.preferredCachedImage(existing: wide, candidate: narrowerSymbol) == narrowerSymbol)
    }

    @Test("An item that changed width is a new picture, not a cut one")
    func resizedItemWins() throws {
        let wide = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let resized = try Self.crop(width: 22, inkFrom: 12, inkTo: 20)
        #expect(Cache.preferredCachedImage(existing: wide, candidate: resized) == resized)
    }

    @Test("Ink that runs into the left edge marks a picture as clipped; a padded or blank one is not")
    func clippedAtLeadingEdge() throws {
        #expect(try Cache.isClippedAtLeadingEdge(Self.crop(width: 24, inkFrom: 0, inkTo: 6)))
        #expect(try Cache.isClippedAtLeadingEdge(Self.crop(width: 17, inkFrom: 0, inkTo: 0.5)))
        #expect(try !Cache.isClippedAtLeadingEdge(Self.crop(width: 24, inkFrom: 4, inkTo: 20)))
        #expect(try !Cache.isClippedAtLeadingEdge(Self.crop(width: 24, inkFrom: 0.5, inkTo: 20)))
        #expect(try !Cache.isClippedAtLeadingEdge(Self.crop(width: 24, inkFrom: 10, inkTo: 10)))
        #expect(try !Cache.isClippedAtLeadingEdge(Self.crop(width: 24, inkFrom: 0, inkTo: 20, alpha: 0.3)), "Faint residue of the bar is not ink")
    }

    @Test("A reveal catch pushed against the left edge loses to the padded picture, and a padded one replaces it")
    func clippedCatchLosesOnReveal() throws {
        let complete = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let pushedLeft = try Self.crop(width: 24, inkFrom: 0, inkTo: 9)
        #expect(Cache.preferredRevealedImage(existing: complete, candidate: pushedLeft) == complete)
        #expect(Cache.preferredRevealedImage(existing: pushedLeft, candidate: complete) == complete)
        #expect(Cache.preferredCachedImage(existing: complete, candidate: pushedLeft) == pushedLeft, "A live item is taken as drawn")
    }

    @Test("An icon that always draws to its left edge, or an item that changed width, still updates on reveal")
    func edgeToEdgeIconStillUpdates() throws {
        let fullWidth = try Self.crop(width: 24, inkFrom: 0, inkTo: 24)
        let fullWidthAgain = try Self.crop(width: 24, inkFrom: 0, inkTo: 23)
        #expect(Cache.preferredRevealedImage(existing: fullWidth, candidate: fullWidthAgain) == fullWidthAgain)

        let padded = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        let resizedToEdge = try Self.crop(width: 30, inkFrom: 0, inkTo: 30)
        #expect(Cache.preferredRevealedImage(existing: padded, candidate: resizedToEdge) == resizedToEdge)
    }

    @Test("Only a capture the user asked for retakes a clipped picture")
    func clippedPictureNeedsARequestedCapture() throws {
        let clipped = try Self.crop(width: 24, inkFrom: 0, inkTo: 6)
        let padded = try Self.crop(width: 24, inkFrom: 4, inkTo: 20)
        #expect(Cache.prewarmNeedsCapture(cachedImage: clipped, wouldAttemptCapture: true, retakesClipped: true))
        #expect(!Cache.prewarmNeedsCapture(cachedImage: clipped, wouldAttemptCapture: true))
        #expect(!Cache.prewarmNeedsCapture(cachedImage: clipped, wouldAttemptCapture: false, retakesClipped: true))
        #expect(!Cache.prewarmNeedsCapture(cachedImage: padded, wouldAttemptCapture: true, retakesClipped: true))
    }

    @Test("Ink bounds are in points, and a blank picture has none")
    func inkBounds() throws {
        let bounds = try #require(Cache.inkBounds(of: Self.crop(width: 24, inkFrom: 4, inkTo: 20)))
        #expect(abs(bounds.minX - 4) < 0.01 && abs(bounds.maxX - 20) < 0.01)
        #expect(abs(bounds.height - 16) < 0.01)
        #expect(try Cache.inkBounds(of: Self.crop(width: 24, inkFrom: 10, inkTo: 10)) == nil)
    }
}
