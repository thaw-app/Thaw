//
//  MenuBarItemImageCacheBackoffTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Live refresh ticks every 2.5 s, slows to 4 s once the bar stops changing, and never speeds up a slower setting.
@Suite("Live refresh back-off ladder")
struct MenuBarItemImageCacheBackoffTests {
    @Test("A changing bar refreshes every 2.5 s")
    func changingBarRefreshesEveryTwoAndAHalfSeconds() {
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 250, changelessStreak: 0) == 2500
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 250, changelessStreak: 4) == 2500
        )
    }

    @Test("An unchanged bar slows to 4 s")
    func unchangedBarSlowsToFourSeconds() {
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 250, changelessStreak: 5) == 4000
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 250, changelessStreak: 500) == 4000
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(
                baseMilliseconds: 250,
                changelessStreak: MenuBarItemImageCache.backoffFloorStreak
            ) == 4000
        )
    }

    @Test("A slower setting is never sped up")
    func slowerSettingIsKept() {
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 5000, changelessStreak: 0) == 5000
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 5000, changelessStreak: 30) == 5000
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 3000, changelessStreak: 0) == 3000
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 3000, changelessStreak: 5) == 4000
        )
    }

    @Test("Degenerate base values still tick at the live rate")
    func clampsDegenerateBase() {
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: 0, changelessStreak: 0) == 2500
        )
        #expect(
            MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: -50, changelessStreak: 70) == 4000
        )
    }
}
