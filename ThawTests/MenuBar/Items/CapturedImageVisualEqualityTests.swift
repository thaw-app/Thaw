//
//  CapturedImageVisualEqualityTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@Suite("Captured image visual equality")
struct CapturedImageVisualEqualityTests {
    @Test("Nil pairs are equal; mixed nil is not")
    func nilPairs() throws {
        #expect(MenuBarItemImageCache.CapturedImage.isVisuallyEqual(nil, nil))
        let image = MenuBarItemImageCache.CapturedImage(
            cgImage: try makeOpaqueImage(width: 2, height: 2),
            scale: 1
        )
        #expect(!MenuBarItemImageCache.CapturedImage.isVisuallyEqual(image, nil))
        #expect(!MenuBarItemImageCache.CapturedImage.isVisuallyEqual(nil, image))
    }

    @Test("Pointer-equal images are visually equal")
    func pointerEquality() throws {
        let cgImage = try makeOpaqueImage(width: 4, height: 4)
        let a = MenuBarItemImageCache.CapturedImage(cgImage: cgImage, scale: 2)
        let b = MenuBarItemImageCache.CapturedImage(cgImage: cgImage, scale: 2)
        #expect(MenuBarItemImageCache.CapturedImage.isVisuallyEqual(a, b))
    }

    @Test("Identical pixels at the same scale are visually equal")
    func identicalPixels() throws {
        let a = MenuBarItemImageCache.CapturedImage(
            cgImage: try makeOpaqueImage(width: 3, height: 2),
            scale: 1
        )
        let b = MenuBarItemImageCache.CapturedImage(
            cgImage: try makeOpaqueImage(width: 3, height: 2),
            scale: 1
        )
        #expect(MenuBarItemImageCache.CapturedImage.isVisuallyEqual(a, b))
    }

    @Test("A scale or pixel mismatch is not visually equal")
    func mismatch() throws {
        let small = try makeOpaqueImage(width: 2, height: 2)
        let large = try makeOpaqueImage(width: 3, height: 2)
        let a = MenuBarItemImageCache.CapturedImage(cgImage: small, scale: 1)
        let b = MenuBarItemImageCache.CapturedImage(cgImage: large, scale: 1)
        let scaled = MenuBarItemImageCache.CapturedImage(cgImage: small, scale: 2)
        #expect(!MenuBarItemImageCache.CapturedImage.isVisuallyEqual(a, b))
        #expect(!MenuBarItemImageCache.CapturedImage.isVisuallyEqual(a, scaled))

        let encoded = try #require(MenuBarCaptureService.encodeBGRA(small))
        var pixels = encoded.pixels
        pixels[0] ^= 0xFF
        let mutatedFrame = MenuBarCaptureService.Frame(
            windowID: 1,
            width: small.width,
            height: small.height,
            bytesPerRow: encoded.bytesPerRow,
            scale: 1,
            pixels: pixels
        )
        let mutated = MenuBarItemImageCache.CapturedImage(
            cgImage: try #require(MenuBarCaptureService.makeImage(from: mutatedFrame)),
            scale: 1
        )
        #expect(!MenuBarItemImageCache.CapturedImage.isVisuallyEqual(a, mutated))
    }
}
