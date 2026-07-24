//
//  MoveFailureBackoffTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterizes the per-item move-failure backoff the bulk-apply loops use
/// to stop one persistently unmovable item (a vanished transient Control
/// Center window, an item whose owning app hangs) from re-triggering a full
/// cursor-hijacking apply on every cache cycle (#736).
final class MoveFailureBackoffTests: XCTestCase {
    /// The interval grows linearly with consecutive failures so a genuinely
    /// stuck item is retried less and less often.
    func testIntervalGrowsWithFailureCount() {
        XCTAssertEqual(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 1), .seconds(30))
        XCTAssertEqual(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 2), .seconds(60))
        XCTAssertEqual(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 4), .seconds(120))
    }

    /// Capped at 5 minutes: an item that recovers (app unhangs, window
    /// reappears with valid bounds) must not wait unboundedly long for its
    /// next attempt.
    func testIntervalIsCappedAtFiveMinutes() {
        XCTAssertEqual(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 10), .seconds(300))
        XCTAssertEqual(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 1000), .seconds(300))
    }

    /// Degenerate input: a zero or negative count is treated as one failure
    /// rather than producing a zero/negative interval.
    func testNonPositiveCountClampsToSingleFailure() {
        XCTAssertEqual(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 0), .seconds(30))
        XCTAssertEqual(MenuBarItemManager.moveFailureBackoffInterval(failureCount: -3), .seconds(30))
    }
}
