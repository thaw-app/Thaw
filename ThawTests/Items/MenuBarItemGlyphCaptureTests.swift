//
//  MenuBarItemGlyphCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// The point size, the blank test, and the pixel comparison the cache uses to skip a republish.
@MainActor
@Suite("Glyph capture value")
struct MenuBarItemGlyphCaptureTests {
    /// A crop filled with one grey level, or left transparent when gray is nil.
    private static func capture(
        width: Int = 20,
        height: Int = 16,
        scale: CGFloat = 1,
        gray: CGFloat? = 1
    ) throws -> MenuBarItemGlyphCapture {
        try ItemsFixture.glyph(width: width, height: height, scale: scale, color: gray.map { CGColor(red: $0, green: $0, blue: $0, alpha: 1) })
    }

    @Test("The point size divides the pixels by the capture's own scale")
    func pointSize() throws {
        #expect(try Self.capture(width: 40, height: 32, scale: 2).pointSize == CGSize(width: 20, height: 16))
        #expect(try Self.capture(width: 40, height: 32, scale: 1).pointSize == CGSize(width: 40, height: 32))
    }

    @Test("A transparent crop is blank and a filled one is not")
    func blankness() throws {
        #expect(try Self.capture(gray: nil).isEffectivelyBlank)
        #expect(try !Self.capture(gray: 1).isEffectivelyBlank)
    }

    @Test("Blankness is stable across repeated reads and copies of the same capture")
    func blanknessIsMemoized() throws {
        let blank = try Self.capture(gray: nil)
        let copy = blank
        #expect(blank.isEffectivelyBlank)
        #expect(blank.isEffectivelyBlank)
        #expect(copy.isEffectivelyBlank)
    }

    @Test("Two missing captures are equal, and a missing one never equals a present one")
    func missingCaptures() throws {
        let capture = try Self.capture()

        #expect(MenuBarItemGlyphCapture.isVisuallyEqual(nil, nil))
        #expect(!MenuBarItemGlyphCapture.isVisuallyEqual(capture, nil))
        #expect(!MenuBarItemGlyphCapture.isVisuallyEqual(nil, capture))
    }

    @Test("A capture equals itself and a separate crop of the same pixels")
    func samePixelsAreEqual() throws {
        let capture = try Self.capture()
        let twin = try Self.capture()

        #expect(MenuBarItemGlyphCapture.isVisuallyEqual(capture, capture))
        #expect(capture.cgImage !== twin.cgImage)
        #expect(MenuBarItemGlyphCapture.isVisuallyEqual(capture, twin))
    }

    @Test("Different pixels, sizes or scales are not equal")
    func differencesAreSeen() throws {
        let capture = try Self.capture()

        #expect(try !MenuBarItemGlyphCapture.isVisuallyEqual(capture, Self.capture(gray: 0.25)))
        #expect(try !MenuBarItemGlyphCapture.isVisuallyEqual(capture, Self.capture(width: 22)))
        #expect(try !MenuBarItemGlyphCapture.isVisuallyEqual(capture, Self.capture(height: 18)))
        #expect(try !MenuBarItemGlyphCapture.isVisuallyEqual(capture, Self.capture(scale: 2)))
    }

    @Test("Equality and hashing follow the image and the scale")
    func equalityAndHashing() throws {
        let capture = try Self.capture()
        let sameImageOtherScale = MenuBarItemGlyphCapture(cgImage: capture.cgImage, scale: 2)
        let sameImageSameScale = MenuBarItemGlyphCapture(cgImage: capture.cgImage, scale: 1)

        #expect(capture == sameImageSameScale)
        #expect(capture.hashValue == sameImageSameScale.hashValue)
        #expect(capture != sameImageOtherScale)
    }

    @Test("The horizontal trim drops transparent side columns and is memoized")
    func horizontalTrim() throws {
        let capture = try ItemsFixture.glyph(
            width: 20, height: 16, ink: CGRect(x: 6, y: 2, width: 8, height: 12), color: CGColor(gray: 0, alpha: 1)
        )

        let trimmed = try #require(capture.horizontallyTrimmedCGImage)

        #expect(trimmed.width == 8)
        #expect(trimmed.height == 16)
        let image = MenuBarItemDisplayImage.capture(capture)
        let bar = ThawBarItemSize(fittingHeight: 8)
        #expect(bar.glyphSize(for: image) == CGSize(width: 4, height: 8))
        #expect(image.targetSize(fittingHeight: 8) == CGSize(width: 10, height: 8))
        #expect(capture.horizontallyTrimmedCGImage === trimmed)
        // A copy of the value shares the memoized trim.
        let copy = capture
        #expect(copy.horizontallyTrimmedCGImage === trimmed)
    }

    @Test("A fully transparent crop has nothing to trim to")
    func trimOfBlankCrop() throws {
        #expect(try Self.capture(gray: nil).horizontallyTrimmedCGImage == nil)
    }

    @Test("Same-size crops with different pixels are not visually equal")
    func differentPixelsDiffer() throws {
        #expect(try !MenuBarItemGlyphCapture.isVisuallyEqual(Self.capture(gray: 1), Self.capture(gray: 0.2)))
        #expect(try MenuBarItemGlyphCapture.isVisuallyEqual(Self.capture(gray: 0.5), Self.capture(gray: 0.5)))
    }
}
