//
//  ThawBarItemSizeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Thaw Bar item size")
struct ThawBarItemSizeTests {
    @Test("The default is the menu bar's own size")
    func defaultIsFullSize() {
        let sizing = ThawBarItemSize(fittingHeight: 24)
        #expect(sizing.scale == 1)
        #expect(sizing.isFullSize)
        #expect(ThawBarItemSize.defaultScale == ThawBarItemSize.maximumScale)
        #expect(ThawBarItemSize.scaleRange == 0.6 ... 1.0)
    }

    @Test("Stored values are clamped to the range, and a value that isn't a number is the default", arguments: [
        (0.1, 0.6), (0.6, 0.6), (0.75, 0.75), (1.0, 1.0), (2.5, 1.0), (-1, 0.6),
        (Double.nan, 1.0), (Double.infinity, 1.0), (-Double.infinity, 1.0),
    ])
    func clamping(value: Double, expected: Double) {
        #expect(ThawBarItemSize.clampedScale(value) == expected)
        #expect(ThawBarItemSize(fittingHeight: 24, scale: value).scale == CGFloat(expected))
    }

    @Test("At full size glyphs, rows and gaps are exactly what they were before the setting")
    func fullSizeChangesNothing() {
        let sizing = ThawBarItemSize(fittingHeight: 37, scale: 1, displayScale: 2)
        let fitted = CGSize(width: 33.5, height: 37)
        #expect(sizing.scaledGlyphSize(fitted) == fitted)
        #expect(sizing.rowHeight(fitting: 33) == 33)
        #expect(sizing.spacing(7) == 7)
    }

    @Test("A smaller size shrinks a glyph's height and width by the same share, on whole pixels")
    func glyphScalesKeepingShape() {
        let sizing = ThawBarItemSize(fittingHeight: 24, scale: 0.7, displayScale: 2)
        let size = sizing.scaledGlyphSize(CGSize(width: 36, height: 24))
        // 24 × 0.7 = 16.8 pt, 33.6 px, rounds to 34 px.
        #expect(size.height == 17)
        #expect(size.width == 25.5)
        #expect((size.height * 2).rounded() == size.height * 2)
        #expect((size.width * 2).rounded() == size.width * 2)
    }

    @Test("Pixel rounding follows the display's backing scale", arguments: [
        (CGFloat(1), CGFloat(17)), (CGFloat(2), CGFloat(16.5)), (CGFloat(3), CGFloat(16.666_666_666_666_668)),
    ])
    func pixelGrid(displayScale: CGFloat, expected: CGFloat) {
        let sizing = ThawBarItemSize(fittingHeight: 37, scale: 0.6, displayScale: displayScale)
        // 27.5 × 0.6 = 16.5 pt.
        let height = sizing.scaledGlyphSize(CGSize(width: 27.5, height: 27.5)).height
        #expect(abs(height - expected) < 0.000_1)
    }

    @Test("A glyph never scales to nothing")
    func neverVanishes() {
        let sizing = ThawBarItemSize(fittingHeight: 24, scale: 0.6, displayScale: 1)
        let size = sizing.scaledGlyphSize(CGSize(width: 0.4, height: 0.4))
        #expect(size.width >= 1)
        #expect(size.height >= 1)
    }

    @Test("Empty and zero sizes pass through untouched")
    func degenerateSizes() {
        let sizing = ThawBarItemSize(fittingHeight: 24, scale: 0.6)
        #expect(sizing.scaledGlyphSize(.zero) == .zero)
        #expect(sizing.scaledGlyphSize(CGSize(width: 10, height: 0)) == CGSize(width: 10, height: 0))
        #expect(sizing.rowHeight(fitting: 0) == 0)
        #expect(sizing.spacing(0) == 0)
    }

    @Test("Rows and gaps shrink with the items", arguments: [0.6, 0.8, 0.9])
    func rowsAndGapsFollow(scale: Double) {
        let sizing = ThawBarItemSize(fittingHeight: 37, scale: scale, displayScale: 2)
        let row = sizing.rowHeight(fitting: 37)
        let gap = sizing.spacing(10)
        #expect(row < 37)
        #expect(abs(row - 37 * CGFloat(scale)) <= 0.25)
        #expect(gap < 10)
        #expect(abs(gap - 10 * CGFloat(scale)) <= 0.25)
    }

    @Test("A non-positive backing scale counts as 1")
    func badDisplayScale() {
        let sizing = ThawBarItemSize(fittingHeight: 24, scale: 0.7, displayScale: 0)
        #expect(sizing.displayScale == 1)
        #expect(sizing.scaledGlyphSize(CGSize(width: 24, height: 24)) == CGSize(width: 17, height: 17))
    }
}
