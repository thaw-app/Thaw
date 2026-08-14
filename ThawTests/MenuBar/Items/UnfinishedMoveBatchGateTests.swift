//
//  UnfinishedMoveBatchGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the arm that withholds the live arrangement from the saved
/// order after a bulk apply gave up partway.
///
/// A batch that fails leaves the bar wherever it stopped. Recording that as
/// the user's layout replaces the order the batch was restoring, so the next
/// pass plans against the partial result and shifts things a little further
/// again (#900). The arm is cleared only by a clean apply or an explicit user
/// move; elapsed time cannot make a partial result authoritative.
@Suite("Unfinished move batch gate")
struct UnfinishedMoveBatchGateTests {
    private let clock = ContinuousClock()

    /// The ordinary case: every apply so far enacted what it planned, so
    /// nothing is withheld.
    @Test("No arm does not block the save")
    func noArmDoesNotBlock() {
        #expect(
            !MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: nil
            )
        )
    }

    /// The cache cycle immediately after a failed batch is the one that
    /// would persist the wreckage, so it has to be covered.
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

    /// A failed batch is not an order of record merely because time passed.
    /// The latch is cleared only by a clean apply or an explicit user move.
    @Test("An old unfinished batch still blocks the save")
    func oldUnfinishedBatchStillBlocks() {
        let armedAt = clock.now
        #expect(
            MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: armedAt
            )
        )
    }

    /// A direct Cmd-drag or a successful Layout editor drag is an explicit
    /// choice to make the current arrangement authoritative.
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
