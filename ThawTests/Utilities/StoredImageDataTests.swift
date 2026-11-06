//
//  StoredImageDataTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@Suite("Picked images stored in preferences")
struct StoredImageDataTests {
    /// A PNG of the given size whose pixels vary, so it compresses poorly and stays large.
    private func noisePNG(width: Int, height: Int) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let pixels = try #require(bitmap.bitmapData)
        var seed: UInt32 = 12345
        for index in 0 ..< bitmap.bytesPerRow * height {
            seed = seed &* 1_103_515_245 &+ 12345
            pixels[index] = UInt8(truncatingIfNeeded: seed >> 16)
        }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test("Data that isn't an image is refused")
    func refusesUndecodableData() {
        #expect(throws: StoredImageData.Failure.self) {
            try StoredImageData.prepared(Data("not an image".utf8))
        }
    }

    @Test("A small image is stored as picked")
    func keepsSmallImage() throws {
        let data = try noisePNG(width: 20, height: 16)
        #expect(data.count <= StoredImageData.maximumByteCount)
        #expect(try StoredImageData.prepared(data) == data)
    }

    @Test("A large image is redrawn smaller, keeping its shape")
    func shrinksLargeImage() throws {
        let data = try noisePNG(width: 600, height: 300)
        #expect(data.count > StoredImageData.maximumByteCount)
        let stored = try StoredImageData.prepared(data)
        #expect(stored.count <= StoredImageData.maximumByteCount)
        let bitmap = try #require(NSBitmapImageRep(data: stored))
        #expect(bitmap.pixelsWide == StoredImageData.maximumPixelLength)
        #expect(bitmap.pixelsHigh == StoredImageData.maximumPixelLength / 2)
    }
}
