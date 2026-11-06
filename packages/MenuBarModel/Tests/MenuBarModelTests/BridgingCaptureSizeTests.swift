//
//  BridgingCaptureSizeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Foundation
@testable import MenuBarModel
import Testing

/// The degenerate-size gate in Bridging.captureWindowsImageSCK: a window
/// server that has not laid the bar out answers a sliver, which must fail so
/// callers fall back rather than cache it as a glyph or sample it as a colour.
struct BridgingCaptureSizeTests {
    @Test("A one-pixel strip is rejected")
    func rejectsObservedSliver() {
        #expect(!Bridging.isPlausibleCaptureSize(width: 1470, height: 1))
        #expect(!Bridging.isPlausibleCaptureSize(width: 2940, height: 1))
    }

    @Test("Empty and single-pixel captures are rejected")
    func rejectsEmptyAndOnePixel() {
        #expect(!Bridging.isPlausibleCaptureSize(width: 0, height: 0))
        #expect(!Bridging.isPlausibleCaptureSize(width: 1, height: 40))
        #expect(!Bridging.isPlausibleCaptureSize(width: 40, height: 1))
    }

    @Test("A real menu bar capture is accepted")
    func acceptsMenuBarCapture() {
        #expect(Bridging.isPlausibleCaptureSize(width: 2940, height: 66))
        #expect(Bridging.isPlausibleCaptureSize(width: 2, height: 2))
    }
}
