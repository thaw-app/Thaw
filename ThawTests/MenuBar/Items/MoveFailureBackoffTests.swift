//
//  MoveFailureBackoffTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the per-item move-failure backoff the bulk-apply loops use
/// to stop one persistently unmovable item (a vanished transient Control
/// Center window, an item whose owning app hangs) from re-triggering a full
/// cursor-hijacking apply on every cache cycle (#736).
@Suite("Move failure backoff")
struct MoveFailureBackoffTests {
    /// The interval grows linearly with consecutive failures so a genuinely
    /// stuck item is retried less and less often.
    @Test("The interval grows with the failure count")
    func intervalGrowsWithFailureCount() {
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 1) == .seconds(30))
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 2) == .seconds(60))
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 4) == .seconds(120))
    }

    /// Capped at 5 minutes: an item that recovers (app unhangs, window
    /// reappears with valid bounds) must not wait unboundedly long for its
    /// next attempt.
    @Test("The interval is capped at five minutes")
    func intervalIsCappedAtFiveMinutes() {
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 10) == .seconds(300))
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 1000) == .seconds(300))
    }

    /// Degenerate input: a zero or negative count is treated as one failure
    /// rather than producing a zero/negative interval.
    @Test("A non-positive count clamps to a single failure")
    func nonPositiveCountClampsToSingleFailure() {
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 0) == .seconds(30))
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: -3) == .seconds(30))
    }
}
