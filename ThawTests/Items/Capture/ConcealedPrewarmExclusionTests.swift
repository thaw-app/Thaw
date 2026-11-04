//
//  ConcealedPrewarmExclusionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// A recapture pass during Capture Hidden Items would crop its revealed items as they slide in.
@MainActor
@Suite("Recapture during Capture Hidden Items")
struct ConcealedPrewarmExclusionTests {
    @Test("A recapture pass runs when no hidden-item capture is in progress")
    func runsWhenIdle() {
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        #expect(!cache.standsDownForConcealedPrewarm("test"))
    }

    @Test("A recapture pass stands down while hidden items are being captured, and runs again after")
    func standsDownDuringPrewarm() async {
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        await cache.beginConcealedPrewarm()
        #expect(cache.standsDownForConcealedPrewarm("test"))

        cache.endConcealedPrewarm()
        #expect(!cache.standsDownForConcealedPrewarm("test"))
    }
}
