//
//  CGImageDetachedCopyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

final class CGImageDetachedCopyTests: XCTestCase {
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

    func testDetachedCopyPreservesDimensionsAndPixels() {
        let parent = makeSolidImage(width: 20, height: 20, color: (255, 0, 0, 255))
        guard let cropped = parent.cropping(to: CGRect(x: 5, y: 5, width: 8, height: 8)) else {
            XCTFail("Failed to crop parent image")
            return
        }

        let detached = cropped.detachedCopy()

        XCTAssertEqual(detached.width, cropped.width)
        XCTAssertEqual(detached.height, cropped.height)
        XCTAssertEqual(pixelData(of: detached), pixelData(of: cropped))
    }

    func testDetachedCopyOwnsItsOwnBuffer() {
        let parent = makeSolidImage(width: 40, height: 40, color: (0, 255, 0, 255))
        guard let cropped = parent.cropping(to: CGRect(x: 10, y: 10, width: 6, height: 6)) else {
            XCTFail("Failed to crop parent image")
            return
        }

        let detached = cropped.detachedCopy()

        // A crop shares its parent's data provider, and the parent is far larger
        // than the crop. A detached copy must be redrawn into a buffer sized to
        // its own dimensions, not the parent's.
        XCTAssertNotEqual(cropped.dataProvider, detached.dataProvider)
        XCTAssertEqual(detached.bytesPerRow * detached.height, detached.dataProvider?.data.map(CFDataGetLength) ?? -1)
    }

    func testDetachedCopyHandlesDegenerateOnePixelImage() {
        let image = makeSolidImage(width: 1, height: 1, color: (10, 20, 30, 255))

        let detached = image.detachedCopy()

        XCTAssertEqual(detached.width, 1)
        XCTAssertEqual(detached.height, 1)
        XCTAssertEqual(pixelData(of: detached), pixelData(of: image))
    }
}
