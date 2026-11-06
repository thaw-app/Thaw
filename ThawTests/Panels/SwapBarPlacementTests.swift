//
//  SwapBarPlacementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Center under the status-item span right of the notch, not under the screen's notched center.
@MainActor
struct SwapBarPlacementTests {
    @Test("a strip narrower than the status-item span centres in it")
    func centresUnderTheStatusItems() {
        guard let screen = NSScreen.main else { return }
        let span = screen.auxiliaryTopRightArea ?? screen.frame
        let width: CGFloat = 320
        let x = SwapBarManager.centerX(under: screen, width: width)

        #expect(abs((x + width / 2) - span.midX) < 0.5)
        #expect(x >= screen.frame.minX)
        #expect(x + width <= screen.frame.maxX)
    }

    @Test("a strip wider than the screen is clamped onto it")
    func clampsAnOversizedStrip() {
        guard let screen = NSScreen.main else { return }
        let x = SwapBarManager.centerX(under: screen, width: screen.frame.width + 400)

        // Oversized strips cannot fit both edges; pin the right edge and let the close-button side extend left.
        #expect(abs((x + screen.frame.width + 400) - screen.frame.maxX) < 0.5)
    }
}
