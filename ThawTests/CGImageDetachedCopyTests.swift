//
//  CGImageDetachedCopyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@Suite("CGImage detached copy")
struct CGImageDetachedCopyTests {
    // MARK: - Helpers

    /// Creates an `width` x `height` bitmap where every pixel is `color`.
    private func makeSolidImage(width: Int, height: Int, color: (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        context.setFillColor(
            red: CGFloat(color.0) / 255,
            green: CGFloat(color.1) / 255,
            blue: CGFloat(color.2) / 255,
            alpha: CGFloat(color.3) / 255
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Reads the raw RGBA bytes of `image` into an array.
    private func pixelData(of image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    // MARK: - Tests

    @Test("A detached copy preserves dimensions and pixels")
    func detachedCopyPreservesDimensionsAndPixels() {
        let parent = makeSolidImage(width: 20, height: 20, color: (255, 0, 0, 255))
        guard let cropped = parent.cropping(to: CGRect(x: 5, y: 5, width: 8, height: 8)) else {
            Issue.record("Failed to crop parent image")
            return
        }

        let detached = cropped.detachedCopy()

        #expect(detached.width == cropped.width)
        #expect(detached.height == cropped.height)
        #expect(pixelData(of: detached) == pixelData(of: cropped))
    }

    @Test("A detached copy owns its own buffer")
    func detachedCopyOwnsItsOwnBuffer() {
        let parent = makeSolidImage(width: 40, height: 40, color: (0, 255, 0, 255))
        guard let cropped = parent.cropping(to: CGRect(x: 10, y: 10, width: 6, height: 6)) else {
            Issue.record("Failed to crop parent image")
            return
        }

        let detached = cropped.detachedCopy()

        // A crop shares its parent's data provider, and the parent is far larger
        // than the crop. A detached copy must be redrawn into a buffer sized to
        // its own dimensions, not the parent's.
        #expect(cropped.dataProvider != detached.dataProvider)
        #expect(detached.bytesPerRow * detached.height == detached.dataProvider?.data.map(CFDataGetLength) ?? -1)
    }

    /// Creates a `width` x `height` 8-bit mask. A mask has no color space,
    /// which is the condition that sends `detachedCopy` down its fallback.
    private func makeMaskImage(width: Int, height: Int) -> CGImage? {
        let bytes = [UInt8](repeating: 128, count: width * height)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else {
            return nil
        }
        return CGImage(
            maskWidth: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            provider: provider,
            decode: nil,
            shouldInterpolate: false
        )
    }

    @Test("A color-spaceless image falls back to device RGB")
    func detachedCopyFallsBackToDeviceRGBForAColorSpacelessImage() throws {
        // Every other case here is device-RGB, so it is served by the
        // preserve-the-source-color-space path and never reaches the
        // fallback. A mask reports a nil color space, so there is nothing
        // to preserve and the device-RGB path is the only way to produce a
        // detached buffer at all.
        let mask = try #require(makeMaskImage(width: 12, height: 9))
        #expect(mask.colorSpace == nil, "a mask is only a valid fixture here while it has no color space")

        let detached = mask.detachedCopy()

        #expect(detached.width == 12)
        #expect(detached.height == 9)
        #expect(detached.colorSpace?.model == .rgb, "the fallback redraws into device RGB")
        #expect(mask.dataProvider != detached.dataProvider, "the copy must own its buffer")
    }

    @Test("A one-pixel image detaches cleanly")
    func detachedCopyHandlesDegenerateOnePixelImage() {
        let image = makeSolidImage(width: 1, height: 1, color: (10, 20, 30, 255))

        let detached = image.detachedCopy()

        #expect(detached.width == 1)
        #expect(detached.height == 1)
        #expect(pixelData(of: detached) == pixelData(of: image))
    }
}
