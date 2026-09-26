//
//  CaptureInspectorBandTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Regression tests for #1033, where the Capture Inspector showed the
/// frontmost app instead of the menu bar.
///
/// The band becomes `SCStreamConfiguration.sourceRect`, which is
/// top-left-origin, but was built from bottom-left-origin `NSScreen.frame`,
/// so it selected the bottom strip. Both bands have the same size, so
/// nothing downstream could reject it.
@Suite("Capture inspector band")
struct CaptureInspectorBandTests {
    /// A 1728×1117pt built-in display at the Core Graphics global origin.
    private static let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private static let menuBarHeight: CGFloat = 33

    @Test("The band sits at the top edge of the display")
    func bandStartsAtDisplayTop() {
        let band = CaptureInspectorSection.menuBarBand(
            inDisplayBounds: Self.display,
            menuBarHeight: Self.menuBarHeight
        )
        // Top-left origin: the menu bar begins at the display's own minY.
        #expect(band.minY == Self.display.minY)
        #expect(band.maxY == Self.display.minY + Self.menuBarHeight)
    }

    @Test("The band is not the bottom strip the AppKit reading produced")
    func bandIsNotTheAppKitMirroredStrip() {
        let band = CaptureInspectorSection.menuBarBand(
            inDisplayBounds: Self.display,
            menuBarHeight: Self.menuBarHeight
        )
        // What the pre-fix code produced: NSScreen.frame.maxY - menuBarHeight.
        let mirrored = Self.display.maxY - Self.menuBarHeight
        #expect(band.minY != mirrored)
        #expect(band.maxY < mirrored)
    }

    @Test("The band spans the full width of the display")
    func bandSpansDisplayWidth() {
        let band = CaptureInspectorSection.menuBarBand(
            inDisplayBounds: Self.display,
            menuBarHeight: Self.menuBarHeight
        )
        #expect(band.minX == Self.display.minX)
        #expect(band.width == Self.display.width)
    }

    /// A secondary display sits at a non-zero global origin, which is where an
    /// origin mix-up stops being a pure vertical mirror and starts pointing at
    /// another display entirely.
    @Test("The band follows a display placed above the primary one")
    func bandFollowsOffsetDisplay() {
        let secondary = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let band = CaptureInspectorSection.menuBarBand(
            inDisplayBounds: secondary,
            menuBarHeight: Self.menuBarHeight
        )
        #expect(band.minY == -1080)
        #expect(band.minX == 0)
        #expect(band.width == 1920)
        #expect(band.height == Self.menuBarHeight)
        // The primary display's band must not be reachable from this one.
        #expect(!band.intersects(Self.display))
    }

    @Test("The band keeps the requested height")
    func bandKeepsHeight() {
        for height in [24.0, 33.0, 37.0, 44.0] as [CGFloat] {
            let band = CaptureInspectorSection.menuBarBand(
                inDisplayBounds: Self.display,
                menuBarHeight: height
            )
            #expect(band.height == height)
        }
    }
}
