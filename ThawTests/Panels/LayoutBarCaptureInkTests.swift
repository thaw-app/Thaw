//
//  LayoutBarCaptureInkTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Pins which captures Layout re-inks: one grey ink on transparency is drawn in the
/// bar's ink, so icons captured over light and dark parts of the bar match.
@MainActor
@Suite("Layout capture ink")
struct LayoutBarCaptureInkTests {
    /// A 20 by 16 crop with a filled square in the middle on transparency.
    private static func glyph(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil,
            width: 20,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 20 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 5, y: 4, width: 10, height: 8))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 2)
    }

    @Test("Black and white glyphs are re-inked", arguments: [0.0, 1.0])
    func greyGlyphsAreTemplates(level: CGFloat) throws {
        let image = try LayoutBarCaptureInk.drawImage(for: Self.glyph(red: level, green: level, blue: level))
        #expect(image.isTemplate)
        #expect(image.size == CGSize(width: 10, height: 8))
    }

    @Test("A colour icon keeps its own pixels")
    func colourIconsStayAsCaptured() throws {
        let image = try LayoutBarCaptureInk.drawImage(for: Self.glyph(red: 0.1, green: 0.4, blue: 0.95))
        #expect(!image.isTemplate)
    }

    @Test("A placeholder icon is lighter as a template and faded while disabled", arguments: [
        (true, true, 0.8), (true, false, 0.9), (false, true, 0.5), (false, false, 0.5),
    ])
    func placeholderFraction(isEnabled: Bool, isTemplate: Bool, expected: CGFloat) {
        #expect(LayoutBarCaptureInk.placeholderFraction(isEnabled: isEnabled, isTemplate: isTemplate) == expected)
    }
}
