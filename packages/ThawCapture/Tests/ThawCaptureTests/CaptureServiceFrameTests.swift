//
//  CaptureServiceFrameTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import ThawCapture

@Suite("Capture service frame decoding")
struct CaptureServiceFrameTests {
    private static func frame(width: Int, height: Int, bytesPerRow: Int, byteCount: Int) -> CaptureServiceFrame {
        CaptureServiceFrame(
            pixelData: Data(count: byteCount),
            pixelWidth: width,
            pixelHeight: height,
            bytesPerRow: bytesPerRow,
            windowFrame: CGRect(x: 0, y: 0, width: 4, height: 2),
            scale: 1
        )
    }

    @Test("A well-formed frame decodes to an image of its size")
    func wellFormedFrameDecodes() throws {
        let image = try #require(Self.frame(width: 4, height: 2, bytesPerRow: 16, byteCount: 32).makeImage())

        #expect(image.width == 4)
        #expect(image.height == 2)
    }

    @Test("A width whose stride overflows Int is rejected without trapping")
    func strideOverflowIsRejected() {
        #expect(Self.frame(width: Int.max / 2, height: 1, bytesPerRow: Int.max, byteCount: 16).makeImage() == nil)
        #expect(CaptureServiceFrame.wireByteCount(pixelWidth: Int.max / 2, pixelHeight: 1, bytesPerRow: Int.max) == nil)
    }

    @Test("A row count whose byte total overflows Int is rejected without trapping")
    func byteCountOverflowIsRejected() {
        #expect(Self.frame(width: 4, height: Int.max, bytesPerRow: 16, byteCount: 16).makeImage() == nil)
        #expect(CaptureServiceFrame.wireByteCount(pixelWidth: 4, pixelHeight: Int.max, bytesPerRow: 16) == nil)
    }

    @Test("Short strides, empty dimensions and short data are rejected")
    func malformedMetadataIsRejected() {
        #expect(CaptureServiceFrame.wireByteCount(pixelWidth: 4, pixelHeight: 2, bytesPerRow: 15) == nil)
        #expect(CaptureServiceFrame.wireByteCount(pixelWidth: 0, pixelHeight: 2, bytesPerRow: 16) == nil)
        #expect(CaptureServiceFrame.wireByteCount(pixelWidth: 4, pixelHeight: -1, bytesPerRow: 16) == nil)
        #expect(CaptureServiceFrame.wireByteCount(pixelWidth: 4, pixelHeight: 2, bytesPerRow: 20) == 40)
        #expect(Self.frame(width: 4, height: 2, bytesPerRow: 16, byteCount: 31).makeImage() == nil)
    }
}
