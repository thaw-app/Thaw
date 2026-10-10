//
//  MenuBarItemImageCacheBackoffTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Static-bar refresh honors the slider through grace ticks, then slows toward 1 Hz without exceeding the chosen rate.
@Suite("Live refresh back-off ladder")
struct MenuBarItemImageCacheBackoffTests {
    @Test("grace ticks hold the slider's rate exactly")
    func graceHoldsBaseRate() {
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 33, changelessStreak: 0) == 33
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 33, changelessStreak: 4) == 33
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 1000, changelessStreak: 4) == 1000
        )
    }

    @Test("mid tier slows to a third, clamped to 100–333 ms")
    func midTierBacksOff() {
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 33, changelessStreak: 5) == 99
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 50, changelessStreak: 30) == 150
        )
        // 200 ms × 3 exceeds the 333 ms clamp.
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 200, changelessStreak: 59) == 333
        )
    }

    @Test("floor tier settles at 1 Hz and never speeds a slow slider up")
    func floorTopsOutAtOneHertz() {
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 33, changelessStreak: 60) == 1000
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 1000, changelessStreak: 500) == 1000
        )
        // A 1 fps slider must never back off to a faster tick.
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 1000, changelessStreak: 30) == 1000
        )
    }

    @Test("degenerate base values clamp to a positive tick")
    func clampsDegenerateBase() {
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 0, changelessStreak: 0) == 1
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: -50, changelessStreak: 70) == 1000
        )
    }
}
