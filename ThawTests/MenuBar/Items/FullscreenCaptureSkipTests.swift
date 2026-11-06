//
//  FullscreenCaptureSkipTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Capturing over a full-screen app lights the screen recording indicator.
struct FullscreenCaptureSkipTests {
    @Test("A display showing a full-screen Space is skipped")
    func fullscreenSpaceIsSkipped() {
        #expect(SpaceInfo.isFullscreen(7) { $0 == 7 })
    }

    @Test("A desktop Space, or a display with no known Space, is captured")
    func desktopOrUnknownSpaceIsCaptured() {
        #expect(!SpaceInfo.isFullscreen(3) { $0 == 7 })
        #expect(!SpaceInfo.isFullscreen(nil) { _ in true })
    }
}
