//
//  UnfinishedMoveBatchGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Withholds the live arrangement from the saved order after a bulk apply gave up.
///
/// Saving where a failed batch stopped makes the next pass plan against the
/// partial result and drift further (#900). Only a clean apply or an explicit
/// user move clears it; elapsed time never does.
@Suite("Unfinished move batch gate")
struct UnfinishedMoveBatchGateTests {
    private let clock = ContinuousClock()

    @Test("No arm does not block the save")
    func noArmDoesNotBlock() {
        #expect(
            !MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: nil
            )
        )
    }

    /// The cycle right after a failed batch is the one that would persist it.
    @Test("A batch that just failed blocks the save")
    func freshArmBlocks() {
        let now = clock.now
        #expect(
            MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: now
            )
        )
    }

    /// A recent failure remains non-authoritative while its retry is pending.
    @Test("A recent unfinished batch blocks the save")
    func recentUnfinishedBatchBlocks() {
        let armedAt = clock.now
        #expect(
            MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: armedAt
            )
        )
    }

    /// Only a clean apply or an explicit user move clears the latch, not time.
    @Test("An old unfinished batch still blocks the save")
    func oldUnfinishedBatchStillBlocks() {
        let armedAt = clock.now
        #expect(
            MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: armedAt
            )
        )
    }

    /// A Cmd-drag or successful Layout editor drag makes the current arrangement authoritative.
    @Test("An explicit user move clears the unfinished-batch latch")
    @MainActor
    func explicitUserMoveClearsLatch() {
        let manager = MenuBarItemManager()
        manager.recordBulkApplyOutcome(unenactedMoveCount: 1)
        #expect(manager.hasUnfinishedMoveBatch)

        manager.recordExternalMoveOperation()

        #expect(!manager.hasUnfinishedMoveBatch)
    }
}
