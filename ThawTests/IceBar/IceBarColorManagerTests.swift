//
//  IceBarColorManagerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Covers `IceBarColorManager.colorSamplePercentage(frame:screenFrame:)`.
///
/// The percentage maps the bar's horizontal center onto the screen so the
/// wallpaper/menu-bar color is sampled at the matching offset. The math
/// divides by the width of the screen frame inset by half the bar width on
/// each side. When a horizontal IceBar overflows to the full screen width —
/// a state the bar itself detects at `frame.width == screen.frame.width`
/// (see `IceBar.swift`) — that inset frame collapses to zero width and the
/// division is by zero. The resulting `NaN` flows into `cropRect.x`, so the
/// color is sampled at a garbage offset (or stops updating) instead of the
/// bar's actual center. The guard falls back to `0.5` (the panel's middle)
/// in that degenerate case, which is what these tests lock in.
@Suite("IceBar color sample percentage")
@MainActor
struct IceBarColorManagerTests {
    // MARK: Full-width overflow (regression)

    @Test("A full-width bar samples the panel middle instead of dividing by zero")
    func fullWidthBarSamplesMiddle() {
        let screenWidth: CGFloat = 1920
        let screenFrame = CGRect(x: 0, y: 0, width: screenWidth, height: 1080)

        // The bar has overflowed to span the entire screen: this is the exact
        // state that collapses the inset frame to zero width and previously
        // divided by zero.
        let fullWidthFrame = CGRect(x: 0, y: 0, width: screenWidth, height: 28)

        let percentage = IceBarColorManager.colorSamplePercentage(
            frame: fullWidthFrame,
            screenFrame: screenFrame
        )

        // No NaN/infinity, and the panel's middle is sampled.
        #expect(percentage.isFinite)
        #expect(percentage == 0.5)
    }

    // MARK: Normal (non-degenerate) positioning

    @Test("A centered bar samples the screen middle")
    func centeredBarSamplesMiddle() {
        let screenWidth: CGFloat = 1920
        let screenFrame = CGRect(x: 0, y: 0, width: screenWidth, height: 1080)

        // A 600pt bar centered horizontally on the screen.
        let barWidth: CGFloat = 600
        let centeredFrame = CGRect(
            x: (screenWidth - barWidth) / 2,
            y: 0,
            width: barWidth,
            height: 28
        )

        let percentage = IceBarColorManager.colorSamplePercentage(
            frame: centeredFrame,
            screenFrame: screenFrame
        )

        #expect(percentage.isFinite)
        #expect(percentage == 0.5)
    }

    @Test("A bar at the right edge samples toward the right")
    func rightEdgeBarSamplesRight() {
        let screenWidth: CGFloat = 1920
        let screenFrame = CGRect(x: 0, y: 0, width: screenWidth, height: 1080)

        let barWidth: CGFloat = 600
        let rightFrame = CGRect(
            x: screenWidth - barWidth,
            y: 0,
            width: barWidth,
            height: 28
        )

        let percentage = IceBarColorManager.colorSamplePercentage(
            frame: rightFrame,
            screenFrame: screenFrame
        )

        #expect(percentage.isFinite)
        #expect(percentage > 0.5)
        #expect(percentage <= 1)
    }
}
