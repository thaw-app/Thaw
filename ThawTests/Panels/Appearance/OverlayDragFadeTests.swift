//
//  OverlayDragFadeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The overlay's fade while a menu bar item is dragged.
@Suite("Overlay drag fade")
struct OverlayDragFadeTests {
    @Test("Fading out is quicker than fading back in")
    func outIsQuicker() {
        #expect(OverlayDragFade.duration(from: 1, to: 0, reduceMotion: false) == 0.15)
        #expect(OverlayDragFade.duration(from: 0, to: 1, reduceMotion: false) == 0.2)
    }

    @Test("A fade reversed partway takes only the share the distance left needs")
    func reversalIsScaled() {
        let duration = OverlayDragFade.duration(from: 0.25, to: 1, reduceMotion: false)
        #expect(abs(duration - 0.15) < 0.0001)
        #expect(OverlayDragFade.duration(from: 1, to: 1, reduceMotion: false) == 0)
    }

    @Test("Reduce Motion keeps a short fade instead of a cut")
    func reduceMotionCaps() {
        #expect(OverlayDragFade.duration(from: 1, to: 0, reduceMotion: true) == 0.1)
        #expect(OverlayDragFade.duration(from: 0, to: 1, reduceMotion: true) == 0.1)
    }
}
