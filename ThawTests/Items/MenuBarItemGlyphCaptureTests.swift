//
//  MenuBarItemGlyphCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Pins the value half of MenuBarItemGlyphCapture: its point size, its blank
/// test and the pixel comparison the cache uses to skip a republish.
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
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        if let gray {
            context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: scale)
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
}
