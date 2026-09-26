//
//  CGImageAnalysisTests.swift
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

/// Covers the two `CGImage` analysis helpers in `Extensions.swift`:
/// `averageColor(using:alphaThreshold:option:)` and
/// `isTransparent(alphaThreshold:)`.
///
/// Both are pure functions of pixel data: the average color drives the
/// adaptive tint, and the transparency check decides whether a captured
/// item is worth caching. `isTransparent` has a fast path for known pixel
/// formats and a `TransparencyContext` fallback, so the cases build images
/// in several formats to exercise both.
@Suite("CGImage analysis")
struct CGImageAnalysisTests {
    // MARK: Average color

    @Test("A solid image averages to its own color")
    func solidImageAveragesToItself() throws {
        let image = try makeCanvas(width: 8, height: 8) { context in
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
        let image = try makeCanvas(width: 8, height: 8) { context in
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
        let image = try makeCanvas(width: 8, height: 8) { _ in
            // Nothing drawn: every pixel keeps alpha 0.
        }

        #expect(image.averageColor() == nil)
    }

    @Test("Ignoring alpha pins the alpha component to opaque")
    func ignoringAlphaPinsTheAlphaComponent() throws {
        // Half-transparent white: with a threshold of 0 every pixel counts,
        // so the only difference the option makes is the alpha component.
        let image = try makeCanvas(width: 8, height: 8) { context in
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
        let image = try makeCanvas(width: 8, height: 8) { context in
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

    @Test("A pixel just below the alpha threshold is excluded (round up, not to nearest)")
    func pixelJustBelowThresholdIsExcluded() throws {
        // A fill alpha of 0.334 quantises to the byte round(0.334 * 255) = 85,
        // a normalised alpha of about 0.3333, strictly below 0.334.
        let image = try makeCanvas(width: 4, height: 4) { context in
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.334)
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        // Pixels with alpha at or above the threshold contribute, so every pixel
        // here is excluded and the average must be nil. The byte threshold is
        // ceil(0.334 * 255) = 86; rounding to nearest would give 85 and wrongly
        // admit these pixels.
        #expect(image.averageColor(alphaThreshold: 0.334) == nil)

        // Control: a threshold of 0 admits the same pixels.
        #expect(image.averageColor(alphaThreshold: 0) != nil)
    }

    @Test("An explicit RGB color space is honored")
    func explicitColorSpaceIsUsed() throws {
        let image = try makeCanvas(width: 4, height: 4) { context in
            context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))

        let average = try #require(image.averageColor(using: space))
        let name = try #require(average.colorSpace?.name)
        #expect((name as String) == (CGColorSpace.sRGB as String))
    }

    @Test("A non-RGB color space argument is ignored rather than fatal")
    func nonRGBColorSpaceFallsBack() throws {
        let image = try makeCanvas(width: 4, height: 4) { context in
            context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let grey = CGColorSpaceCreateDeviceGray()

        #expect(image.averageColor(using: grey) != nil)
    }

    @Test("A large image is downsampled rather than refused")
    func largeImageIsHandled() throws {
        let image = try makeCanvas(width: 200, height: 120) { context in
            context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        }

        let components = try #require(image.averageColor()?.components)
        #expect(components[1] > 0.85, "green should dominate, got \(components)")
    }

    @Test("A single-pixel image still averages")
    func singlePixelImageAverages() throws {
        let image = try makeCanvas(width: 1, height: 1) { context in
            context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        let components = try #require(image.averageColor()?.components)
        #expect(components[2] > 0.85, "blue should dominate, got \(components)")
    }

    // MARK: Transparency

    @Test("A fully clear image reads as transparent")
    func clearImageIsTransparent() throws {
        let image = try makeCanvas(width: 8, height: 8) { _ in }

        #expect(image.isTransparent())
    }

    @Test("A fully opaque image does not read as transparent")
    func opaqueImageIsNotTransparent() throws {
        let image = try makeCanvas(width: 8, height: 8) { context in
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        #expect(!image.isTransparent())
    }

    @Test("A single opaque pixel is enough to be non-transparent")
    func oneOpaquePixelDefeatsTransparency() throws {
        let image = try makeCanvas(width: 16, height: 16) { context in
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 15, y: 15, width: 1, height: 1))
        }

        #expect(!image.isTransparent())
    }

    @Test("The alpha threshold decides what counts as transparent")
    func transparencyThresholdIsHonored() throws {
        let image = try makeCanvas(width: 8, height: 8) { context in
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
        let normal = try makeCanvas(width: 8, height: 8) { context in
            if opaque {
                context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
        }

        #expect(fallback.isTransparent() == normal.isTransparent())
    }

    @Test("A single-pixel clear image reads as transparent")
    func singleClearPixelIsTransparent() throws {
        let image = try makeCanvas(width: 1, height: 1) { _ in }

        #expect(image.isTransparent())
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
    }

    // MARK: - Helpers

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
