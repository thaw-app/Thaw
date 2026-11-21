//
//  PartialScanFollowUpTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// A partial scan publishes the cache but leaves the saved-order mirror and overflow balancing to a
/// complete one, which still owes them when it finds the same cache.
@Suite("Partial scan follow-up")
struct PartialScanFollowUpTests {
    @Test("A complete scan that finds a partial scan's cache unchanged runs the work it left")
    func completeScanRunsDeferredWork() {
        #expect(MenuBarItemManager.unchangedCacheOwesDeferredWork(observationOnly: false, awaitsFullScan: true))
    }

    @Test("An unchanged cache owes nothing after a complete scan, and a partial scan never runs the work")
    func nothingOwed() {
        #expect(!MenuBarItemManager.unchangedCacheOwesDeferredWork(observationOnly: false, awaitsFullScan: false))
        #expect(!MenuBarItemManager.unchangedCacheOwesDeferredWork(observationOnly: true, awaitsFullScan: true))
    }
}
