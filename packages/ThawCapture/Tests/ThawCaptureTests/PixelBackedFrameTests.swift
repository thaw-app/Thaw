//
//  PixelBackedFrameTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import ThawCapture

/// Taller menu bars, such as 45 pt on OLED Macs, keep their point-space frames.
struct PixelBackedFrameTests {
    private let displayFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test(arguments: [37.0, 45.0, 49.0])
    func tallPointSpaceBarIsNotMistakenForPixels(height: Double) {
        let pointWindowFrame = CGRect(x: 0, y: 0, width: 1512, height: height)
        #expect(!ScreenCapture.windowFrameAppearsPixelBacked(pointWindowFrame, displayFrame: displayFrame))
        let size = ScreenCapture.hostingCapturePixelSize(
            windowFrame: pointWindowFrame,
            displayFrame: displayFrame,
            reportedScale: 2
        )
        #expect(size.height == Int(height * 2))
    }

    @Test(arguments: [74.0, 90.0, 98.0])
    func tallPixelBackedBarStaysPixelBacked(height: Double) {
        let pixelWindowFrame = CGRect(x: 0, y: 0, width: 3024, height: height)
        #expect(ScreenCapture.windowFrameAppearsPixelBacked(pixelWindowFrame, displayFrame: displayFrame))
    }
}
