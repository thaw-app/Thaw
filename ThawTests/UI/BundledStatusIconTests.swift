//
//  BundledStatusIconTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Bundled status icon pixel budget")
struct BundledStatusIconTests {
    private static func bitmapImage(pixels: Int, points: CGFloat) throws -> NSImage {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = NSSize(width: points, height: points)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    @Test("Menu bar sized representations fit the budget")
    func smallRepresentationsFit() {
        #expect(BundledStatusIcon.fitsPixelBudget([(width: 18, height: 18), (width: 36, height: 36)]))
        #expect(BundledStatusIcon.fitsPixelBudget([(width: 288, height: 96)]))
        #expect(BundledStatusIcon.fitsPixelBudget([(width: 512, height: 512)]))
        #expect(BundledStatusIcon.fitsPixelBudget([]))
    }

    @Test("Vector representations report zero pixels and fit")
    func vectorRepresentationsFit() {
        #expect(BundledStatusIcon.fitsPixelBudget([(width: 0, height: 0)]))
    }

    @Test("Any representation over the budget on either side rejects the image")
    func oversizedRepresentationsAreRejected() {
        #expect(!BundledStatusIcon.fitsPixelBudget([(width: 513, height: 16)]))
        #expect(!BundledStatusIcon.fitsPixelBudget([(width: 16, height: 513)]))
        #expect(!BundledStatusIcon.fitsPixelBudget([(width: 18, height: 18), (width: 20000, height: 20000)]))
    }

    @Test("A small point size backed by a huge bitmap is caught through its representation")
    func hugeBitmapBehindSmallPointSize() throws {
        #expect(try !BundledStatusIcon.fitsPixelBudget(Self.bitmapImage(pixels: 4096, points: 16)))
    }

    @Test("A menu bar sized bitmap passes the image check")
    func smallBitmapPasses() throws {
        #expect(try BundledStatusIcon.fitsPixelBudget(Self.bitmapImage(pixels: 36, points: 18)))
    }
}
