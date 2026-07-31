//
//  CGImageAnalysisTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers the two `CGImage` analysis helpers in `Extensions.swift`:
/// `averageColor(using:alphaThreshold:option:)` and
/// `isTransparent(alphaThreshold:)`.
///
/// Both feed real decisions — the menu bar's average color drives the
/// adaptive tint, and the transparency check decides whether a captured menu
/// bar item is worth caching — and both are pure functions of pixel data, so
/// they can be driven with images built in memory.
///
/// `isTransparent` has a fast path that reads alpha bytes straight from the
/// image's data provider and a `TransparencyContext` fallback for pixel
/// formats it does not recognise. The cases below build images in several
/// formats so both routes are exercised.
@Suite("CGImage analysis")
struct CGImageAnalysisTests {
    // MARK: Average color

    @Test("A solid image averages to its own color")
    func solidImageAveragesToItself() throws {
        let image = try makeImage(width: 8, height: 8) { context in
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        let average = try #require(image.averageColor())
        let components = try #require(average.components)

        #expect(components.count >= 3)
        #expect(components[0] > 0.85, "red should dominate, got \(components)")
        #expect(components[1] < 0.15)
        #expect(components[2] < 0.15)
    }

    @Test("A half-and-half image averages between its two colors")
    func twoToneImageAveragesBetween() throws {
        let image = try makeImage(width: 8, height: 8) { context in
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 4, width: 8, height: 4))
        }

        let average = try #require(image.averageColor())
        let components = try #require(average.components)

        for channel in components.prefix(3) {
            #expect(channel > 0.25 && channel < 0.75, "expected a mid grey, got \(components)")
        }
    }

    @Test("A fully transparent image has no average color")
    func fullyTransparentImageHasNoAverage() throws {
        let image = try makeImage(width: 8, height: 8) { _ in
            // Nothing drawn: every pixel keeps alpha 0.
        }

        #expect(image.averageColor() == nil)
    }

    @Test("Ignoring alpha pins the alpha component to opaque")
    func ignoringAlphaPinsTheAlphaComponent() throws {
        // Half-transparent white: with a threshold of 0 every pixel counts,
        // so the only difference the option makes is the alpha component.
        let image = try makeImage(width: 8, height: 8) { context in
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.5)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        let plain = try #require(image.averageColor(alphaThreshold: 0)?.components)
        let ignoring = try #require(
            image.averageColor(alphaThreshold: 0, option: .ignoreAlpha)?.components
        )

        #expect(plain[3] < 0.9, "the real alpha should be around a half, got \(plain)")
        #expect(ignoring[3] == 1)
    }

    @Test("The alpha threshold decides which pixels count")
    func alphaThresholdSelectsContributingPixels() throws {
        // Half opaque red, half barely-there red.
        let image = try makeImage(width: 8, height: 8) { context in
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
            context.setFillColor(red: 0, green: 0, blue: 1, alpha: 0.1)
            context.fill(CGRect(x: 0, y: 4, width: 8, height: 4))
        }

        // A high threshold drops the faint blue half entirely.
        let strict = try #require(image.averageColor(alphaThreshold: 0.9)?.components)
        #expect(strict[0] > strict[2], "the opaque red half should win, got \(strict)")

        // A threshold of zero lets everything contribute.
        #expect(image.averageColor(alphaThreshold: 0) != nil)
    }

    @Test("An explicit RGB color space is honored")
    func explicitColorSpaceIsUsed() throws {
        let image = try makeImage(width: 4, height: 4) { context in
            context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))

        let average = try #require(image.averageColor(using: space))
        #expect(average.colorSpace?.model == .rgb)
    }

    @Test("A non-RGB color space argument is ignored rather than fatal")
    func nonRGBColorSpaceFallsBack() throws {
        let image = try makeImage(width: 4, height: 4) { context in
            context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let grey = CGColorSpaceCreateDeviceGray()

        #expect(image.averageColor(using: grey) != nil)
    }

    @Test("A large image is downsampled rather than refused")
    func largeImageIsHandled() throws {
        let image = try makeImage(width: 200, height: 120) { context in
            context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        }

        let components = try #require(image.averageColor()?.components)
        #expect(components[1] > 0.85, "green should dominate, got \(components)")
    }

    @Test("A single-pixel image still averages")
    func singlePixelImageAverages() throws {
        let image = try makeImage(width: 1, height: 1) { context in
            context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        let components = try #require(image.averageColor()?.components)
        #expect(components[2] > 0.85, "blue should dominate, got \(components)")
    }

    // MARK: Transparency

    @Test("A fully clear image reads as transparent")
    func clearImageIsTransparent() throws {
        let image = try makeImage(width: 8, height: 8) { _ in }

        #expect(image.isTransparent())
    }

    @Test("A fully opaque image does not read as transparent")
    func opaqueImageIsNotTransparent() throws {
        let image = try makeImage(width: 8, height: 8) { context in
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        #expect(!image.isTransparent())
    }

    @Test("A single opaque pixel is enough to be non-transparent")
    func oneOpaquePixelDefeatsTransparency() throws {
        let image = try makeImage(width: 16, height: 16) { context in
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 15, y: 15, width: 1, height: 1))
        }

        #expect(!image.isTransparent())
    }

    @Test("The alpha threshold decides what counts as transparent")
    func transparencyThresholdIsHonored() throws {
        let image = try makeImage(width: 8, height: 8) { context in
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.2)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        // At the default threshold of 0, any non-zero alpha counts as content.
        #expect(!image.isTransparent())
        // Raised above the pixels' own alpha, the image reads as empty.
        #expect(image.isTransparent(alphaThreshold: 0.5))
    }

    @Test("The fallback path agrees with the fast path", arguments: [true, false])
    func fallbackAgreesWithFastPath(_ opaque: Bool) throws {
        // An image with no explicit byte order is outside the fast path, so
        // this exercises the TransparencyContext fallback.
        let fallback = try makeDefaultByteOrderImage(width: 8, height: 8, opaque: opaque)
        let normal = try makeImage(width: 8, height: 8) { context in
            if opaque {
                context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
        }

        #expect(fallback.isTransparent() == normal.isTransparent())
    }

    @Test("A single-pixel clear image reads as transparent")
    func singleClearPixelIsTransparent() throws {
        let image = try makeImage(width: 1, height: 1) { _ in }

        #expect(image.isTransparent())
    }

    // MARK: - Helpers

    /// Builds a premultiplied-first, 32-bit little-endian RGBA image — the
    /// shape the capture paths produce, and one the fast path recognises.
    private func makeImage(
        width: Int,
        height: Int,
        draw: (CGContext) -> Void
    ) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        )
        draw(context)
        return try #require(context.makeImage())
    }

    /// Builds an image with no explicit byte order. The alpha fast path
    /// bails on `byteOrderDefault` "for safety", so this routes through the
    /// `TransparencyContext` fallback instead.
    private func makeDefaultByteOrderImage(width: Int, height: Int, opaque: Bool) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        )
        if opaque {
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(context.makeImage())
    }
}
