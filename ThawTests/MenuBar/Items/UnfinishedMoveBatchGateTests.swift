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
/// again (#900). The arm expires rather than holding until an apply finally
/// comes back clean, because an item whose owner never responds would
/// otherwise freeze the saved layout for the rest of the session.
@Suite("Unfinished move batch gate")
struct UnfinishedMoveBatchGateTests {
    private let clock = ContinuousClock()

    /// The ordinary case: every apply so far enacted what it planned, so
    /// nothing is withheld.
    @Test("No arm does not block the save")
    func noArmDoesNotBlock() {
        #expect(
            !MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: nil,
                now: clock.now
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
                observedAt: now,
                now: now
            )
        )
    }

    /// The window has to outlast the retry apply, which needs two
    /// consecutive divergence observations before it dispatches.
    @Test("An arm inside the window still blocks")
    func armInsideWindowBlocks() {
        let armedAt = clock.now
        #expect(
            MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: armedAt,
                now: armedAt.advanced(by: .seconds(20)),
                staleness: .seconds(30)
            )
        )
    }

    /// Past the window the user's own rearrangements matter more than a
    /// batch that is evidently not going to succeed.
    @Test("An arm beyond the window stops blocking")
    func armBeyondWindowStopsBlocking() {
        let armedAt = clock.now
        #expect(
            !MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: armedAt,
                now: armedAt.advanced(by: .seconds(31)),
                staleness: .seconds(30)
            )
        )
    }

    /// The boundary is inclusive, matching `confirmedDivergence`. Pinned
    /// because the two windows are meant to stay comparable.
    @Test("An arm exactly at the window boundary still blocks")
    func armAtBoundaryBlocks() {
        let armedAt = clock.now
        #expect(
            MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: armedAt,
                now: armedAt.advanced(by: .seconds(30)),
                staleness: .seconds(30)
            )
        )
    }
}
