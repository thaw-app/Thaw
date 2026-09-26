//
//  ExtensionsRemainderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

// MARK: - Fixtures

/// One 32-bit pixel layout that `CGImage.isTransparent(alphaThreshold:)`
/// claims to read straight out of the image's own bytes, paired with the
/// byte index the alpha component physically occupies under that layout.
///
/// The offsets are the ones the extension's own table asserts: a logical
/// `First` layout read little-endian lands alpha in the *last* byte, and a
/// logical `Last` layout read little-endian lands it in the *first*.
private struct PixelLayout: Sendable, CustomStringConvertible {
    let name: String
    let alphaInfo: CGImageAlphaInfo
    let byteOrder: CGBitmapInfo
    /// The index of the alpha byte within each four-byte pixel.
    let alphaByte: Int

    var description: String {
        name
    }

    /// Every row of the extension's alpha-offset table, in both the
    /// premultiplied and the straight spelling.
    static let all: [PixelLayout] = [
        PixelLayout(
            name: "premultipliedFirst/little (BGRA)",
            alphaInfo: .premultipliedFirst,
            byteOrder: .byteOrder32Little,
            alphaByte: 3
        ),
        PixelLayout(
            name: "first/little (BGRA)",
            alphaInfo: .first,
            byteOrder: .byteOrder32Little,
            alphaByte: 3
        ),
        PixelLayout(
            name: "premultipliedLast/little (ABGR)",
            alphaInfo: .premultipliedLast,
            byteOrder: .byteOrder32Little,
            alphaByte: 0
        ),
        PixelLayout(
            name: "last/little (ABGR)",
            alphaInfo: .last,
            byteOrder: .byteOrder32Little,
            alphaByte: 0
        ),
        PixelLayout(
            name: "premultipliedFirst/big (ARGB)",
            alphaInfo: .premultipliedFirst,
            byteOrder: .byteOrder32Big,
            alphaByte: 0
        ),
        PixelLayout(
            name: "first/big (ARGB)",
            alphaInfo: .first,
            byteOrder: .byteOrder32Big,
            alphaByte: 0
        ),
        PixelLayout(
            name: "premultipliedLast/big (RGBA)",
            alphaInfo: .premultipliedLast,
            byteOrder: .byteOrder32Big,
            alphaByte: 3
        ),
        PixelLayout(
            name: "last/big (RGBA)",
            alphaInfo: .last,
            byteOrder: .byteOrder32Big,
            alphaByte: 3
        ),
    ]
}

/// Builds a 32-bit image every one of whose pixels carries `bytes`, in
/// exactly that physical order.
///
/// Built from a data provider because `CGContext` cannot be created with a
/// big-endian or `Last`-alpha layout, so a context-built fixture could not
/// reach half of the offset table.
private func makeRawImage(
    width: Int,
    height: Int,
    alphaInfo: CGImageAlphaInfo,
    byteOrder: CGBitmapInfo,
    pixel bytes: [UInt8]
) throws -> CGImage {
    var pixels = [UInt8]()
    pixels.reserveCapacity(width * height * 4)
    for _ in 0 ..< (width * height) {
        pixels.append(contentsOf: bytes)
    }
    let provider = try #require(
        CGDataProvider(data: Data(pixels) as CFData),
        "Could not create a data provider"
    )
    return try #require(
        CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue).union(byteOrder),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ),
        "Could not create an image with alphaInfo \(alphaInfo.rawValue) and byte order \(byteOrder.rawValue)"
    )
}

/// A four-byte pixel whose byte at `index` is `alpha` and whose other three
/// bytes are `others`. Filling them with the opposite value means the
/// fixture only gives the expected answer if alpha is read from `index`.
private func makePixel(alpha: UInt8, atByte index: Int, others: UInt8) -> [UInt8] {
    var bytes = [UInt8](repeating: others, count: 4)
    bytes[index] = alpha
    return bytes
}

/// Builds an 8-bit image mask. A mask reports no color space at all and one
/// byte per pixel, which is the pair of conditions the two fallbacks below
/// are written for.
private func makeMask(width: Int, height: Int, value: UInt8) throws -> CGImage {
    let provider = try #require(
        CGDataProvider(data: Data([UInt8](repeating: value, count: width * height)) as CFData),
        "Could not create a data provider"
    )
    return try #require(
        CGImage(
            maskWidth: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            provider: provider,
            decode: nil,
            shouldInterpolate: false
        ),
        "Could not create an image mask"
    )
}

// MARK: - Suite

/// Covers what the sibling Extensions and CGImage suites leave behind in
/// `Utilities/Extensions.swift`: the refusals and format-dependent branches
/// of the `CGColor` and `CGImage` helpers.
///
/// - **The alpha-offset table in `isTransparent`.** The fast path picks the
///   alpha byte from the alpha position and the byte order. Other suites only
///   use premultiplied-first little-endian (the screen capture format); a
///   transposed row would read a color channel as alpha and drop or cache
///   the wrong item images.
/// - **The two fallbacks out of the fast path**: a pixel format that is not
///   32-bit, and an alpha format with no alpha channel.
/// - **`averageColor`'s color space resolution**: the fall-through to
///   Display P3, and the refusal when the space cannot back an 8-bit context.
/// - **`CGColor.brightness`'s `nil` branch**, reachable through a pattern
///   color, which has no numeric components to convert.
///
/// Not covered:
///
/// - `NSScreen` members, which read the attached displays, call `Bridging`
///   or Accessibility, or mutate display caches the host app shares.
/// - `NSStatusItem.showMenu(_:)`, which runs a modal menu tracking loop.
/// - `NSPanel.waitForInvisibleWithKVO`'s cancellation arm, which needs a
///   panel that has been ordered in.
/// - Refusals no fixture can produce: the `@unknown default` arms, the
///   `alphaOnly` offset row (Core Graphics rejects a 32-bit `alphaOnly`
///   image), the short-buffer guard (rejected at creation), and the "context
///   could not be created" arms of `isTransparentSlow` and `detachedCopy`.
@Suite("Extensions remainder")
struct ExtensionsRemainderTests {
    // MARK: - CGColor

    /// `brightness` decides whether the menu bar tint is treated as light or
    /// dark. Its `nil` branch is the only thing standing between a color it
    /// cannot measure and a caller acting on a garbage number.
    @MainActor
    @Suite("A color that cannot be measured")
    struct CGColorRefusalTests {
        /// A pattern color carries a drawing callback instead of components,
        /// so there is nothing for Core Graphics to match into device RGB.
        /// It is the only color that can be built in process whose conversion
        /// genuinely fails.
        private func patternColor() throws -> CGColor {
            var callbacks = CGPatternCallbacks(
                version: 0,
                drawPattern: { _, context in
                    context.setFillColor(gray: 0, alpha: 1)
                    context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
                },
                releaseInfo: nil
            )
            let pattern = try #require(
                CGPattern(
                    info: nil,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    matrix: .identity,
                    xStep: 1,
                    yStep: 1,
                    tiling: .constantSpacing,
                    isColored: true,
                    callbacks: &callbacks
                ),
                "Could not create a pattern"
            )
            let space = try #require(
                CGColorSpace(patternBaseSpace: nil),
                "Could not create a pattern color space"
            )
            var alpha: CGFloat = 1
            return try #require(
                CGColor(patternSpace: space, pattern: pattern, components: &alpha),
                "Could not create a pattern color"
            )
        }

        @Test("A color that will not convert to RGB has no brightness")
        func unconvertibleColorHasNoBrightness() throws {
            let color = try patternColor()

            // The conversion, not the component count, is what fails: a
            // pattern color does report a component, its alpha.
            #expect(color.numberOfComponents == 1)
            #expect(color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil) == nil)
            #expect(color.brightness == nil)
        }
    }

    // MARK: - CGImage transparency by pixel format

    /// The fast path in `isTransparent(alphaThreshold:)` reads alpha bytes
    /// straight out of the image's data provider, which means it has to work
    /// out where the alpha byte sits from the alpha info and the byte order
    /// on its own. Each case below writes the *opposite* value into the three
    /// non-alpha bytes, so reading any byte but the right one flips the
    /// answer.
    @Suite("Reading alpha out of a pixel")
    struct TransparencyByPixelFormatTests {
        @Test("A clear image reads as transparent in every layout", arguments: PixelLayout.all)
        fileprivate func clearImageIsTransparentInEveryLayout(_ layout: PixelLayout) throws {
            let image = try makeRawImage(
                width: 4,
                height: 3,
                alphaInfo: layout.alphaInfo,
                byteOrder: layout.byteOrder,
                pixel: makePixel(alpha: 0, atByte: layout.alphaByte, others: 255)
            )

            #expect(image.isTransparent(), "every byte but the alpha byte holds 255 here")
        }

        @Test("An opaque image reads as opaque in every layout", arguments: PixelLayout.all)
        fileprivate func opaqueImageIsNotTransparentInEveryLayout(_ layout: PixelLayout) throws {
            let image = try makeRawImage(
                width: 4,
                height: 3,
                alphaInfo: layout.alphaInfo,
                byteOrder: layout.byteOrder,
                pixel: makePixel(alpha: 255, atByte: layout.alphaByte, others: 0)
            )

            #expect(!image.isTransparent(), "every byte but the alpha byte holds 0 here")
        }

        /// The threshold is applied to the same byte, so a layout that reads
        /// the wrong byte would also mis-apply it.
        @Test("The threshold is applied to the alpha byte in every layout", arguments: PixelLayout.all)
        fileprivate func thresholdAppliesToTheAlphaByte(_ layout: PixelLayout) throws {
            let image = try makeRawImage(
                width: 4,
                height: 3,
                alphaInfo: layout.alphaInfo,
                byteOrder: layout.byteOrder,
                pixel: makePixel(alpha: 50, atByte: layout.alphaByte, others: 255)
            )

            #expect(!image.isTransparent(alphaThreshold: 0.1))
            #expect(image.isTransparent(alphaThreshold: 0.5))
        }

        /// An image whose alpha info says there is no alpha channel is opaque by
        /// definition, even when, as here, every byte in it is zero.
        @Test("An image with no alpha channel is never transparent", arguments: [
            (CGImageAlphaInfo.noneSkipFirst, CGBitmapInfo.byteOrder32Little),
            (CGImageAlphaInfo.noneSkipLast, CGBitmapInfo.byteOrder32Big),
            (CGImageAlphaInfo.noneSkipFirst, CGBitmapInfo.byteOrder32Big),
            (CGImageAlphaInfo.noneSkipLast, CGBitmapInfo.byteOrder32Little),
        ])
        func alphaLessImageIsNeverTransparent(
            alphaInfo: CGImageAlphaInfo,
            byteOrder: CGBitmapInfo
        ) throws {
            let image = try makeRawImage(
                width: 4,
                height: 3,
                alphaInfo: alphaInfo,
                byteOrder: byteOrder,
                pixel: [0, 0, 0, 0]
            )

            #expect(!image.isTransparent())
            #expect(!image.isTransparent(alphaThreshold: 0.9))
        }

        /// A saturated threshold would call every pixel transparent, so the
        /// question stops being about the pixels at all.
        @Test("A threshold of one or more calls nothing transparent")
        func saturatedThresholdRefusesEarly() throws {
            let image = try makeRawImage(
                width: 4,
                height: 3,
                alphaInfo: .premultipliedFirst,
                byteOrder: .byteOrder32Little,
                pixel: [0, 0, 0, 0]
            )

            #expect(!image.isTransparent(alphaThreshold: 1))
            #expect(!image.isTransparent(alphaThreshold: 2))
        }

        /// Anything that is not four bytes per pixel is handed to the
        /// `TransparencyContext` fallback, which redraws the image into an
        /// alpha-only context instead of reading its bytes. A mask is the
        /// cheapest such image to build, at one byte per pixel.
        ///
        /// A mask value of 0 paints; 255 paints nothing. So the all-zero mask
        /// is the opaque one, which is also a useful guard against the
        /// fallback simply reporting the raw bytes.
        @Test("A pixel format the fast path does not know is measured by redrawing", arguments: [
            (UInt8(0), false),
            (UInt8(255), true),
        ])
        func unrecognisedPixelFormatUsesTheFallback(maskValue: UInt8, expected: Bool) throws {
            let mask = try makeMask(width: 6, height: 6, value: maskValue)

            #expect(mask.bitsPerPixel == 8, "the fixture only exercises the fallback while it is not 32-bit")
            #expect(mask.isTransparent() == expected)
        }
    }

    // MARK: - CGImage average color

    /// `averageColor` picks the color space it works in before it looks at a
    /// single pixel: the caller's, else the image's, else Display P3. Both
    /// the last step and the refusal that follows a space it cannot draw into
    /// decide whether the menu bar's adaptive tint gets a color or nothing.
    @Suite("Choosing a color space to average in")
    struct AverageColorSpaceTests {
        /// A mask has no color space of its own, so it is the only image that
        /// reaches the Display P3 fall-through. A mask value of 0 paints the
        /// context's default fill (opaque black), keeping every pixel above the
        /// default alpha threshold.
        @Test("An image with no color space of its own is averaged in Display P3")
        func colorSpacelessImageFallsBackToDisplayP3() throws {
            let mask = try makeMask(width: 6, height: 6, value: 0)
            #expect(mask.colorSpace == nil, "the fixture only means anything while the mask has no color space")

            let average = try #require(mask.averageColor())
            let name = try #require(average.colorSpace?.name)

            #expect((name as String) == (CGColorSpace.displayP3 as String))

            let components = try #require(average.components)
            #expect(components.count == 4)
            #expect(components[3] > 0.99, "the mask paints opaque, so the average is opaque")
        }

        /// A caller's color space is only honoured when it is an RGB one, and
        /// a mask offers nothing to fall back to, so the requested space is
        /// unambiguously the one in force.
        @Test("An RGB color space from the caller wins over the fall-through")
        func callerColorSpaceWinsOverTheFallback() throws {
            let mask = try makeMask(width: 6, height: 6, value: 0)
            let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))

            let average = try #require(mask.averageColor(using: sRGB))
            let name = try #require(average.colorSpace?.name)

            #expect((name as String) == (CGColorSpace.sRGB as String))
        }

        /// `extendedSRGB` passes the RGB-model test the resolution step
        /// applies, but its components are outside 0...1, so it cannot back
        /// the eight-bit context the average is computed in. The only honest
        /// answer is no color: a fabricated one would be blended into the
        /// menu bar tint as if it had been measured.
        @Test("A color space that cannot back an eight-bit context yields no average")
        func unusableColorSpaceYieldsNoAverage() throws {
            let image = try makeOpaqueImage(width: 8, height: 8)
            let extended = try #require(CGColorSpace(name: CGColorSpace.extendedSRGB))
            #expect(extended.model == .rgb, "the fixture only reaches the refusal while it looks like an RGB space")

            // The same image averages perfectly well in a space that can.
            #expect(image.averageColor() != nil)

            #expect(image.averageColor(using: extended) == nil)
        }

        /// Every pixel of a mask painted with 255 is left untouched, so every
        /// pixel falls below the alpha threshold and there is nothing left to
        /// divide by.
        @Test("An image with nothing above the alpha threshold has no average")
        func fullyBelowThresholdYieldsNoAverage() throws {
            let mask = try makeMask(width: 6, height: 6, value: 255)

            #expect(mask.averageColor() == nil)
        }
    }
}
