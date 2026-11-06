//
//  RevealBatchSizeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Testing
@testable import Thaw

/// Reveal one item at a time on notched displays so overflow chevrons do not contaminate thumbnails.
/// Wider notchless lanes can batch reveals to reduce repeated transitions.
@Suite("Reveal batch size")
struct RevealBatchSizeTests {
    @Test("A notched display reveals one item at a time")
    func notchedDisplayRevealsOneItem() {
        #expect(MenuBarItemImageCache.revealBatchSize(hasNotch: true) == 1)
    }

    @Test("A notchless display keeps the grouped batch")
    func notchlessDisplayKeepsTheGroupedBatch() {
        #expect(MenuBarItemImageCache.revealBatchSize(hasNotch: false) > 1)
    }
}
