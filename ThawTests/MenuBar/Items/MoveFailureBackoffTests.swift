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

/// Characterizes which failures `move` has already filed with the ledger by
/// the time it throws, so a catch clause that files again does not charge one
/// failed move twice.
///
/// Double-filing was invisible while it only widened a backoff window, but it
/// made the "wait for another failure before marking" rule meaningless: both
/// halves were consumed in the same instant. In the #687 log, 1Password was
/// marked unresponsive one millisecond after the line saying it was still
/// waiting for a second failure.
@Suite("Move failure double filing")
struct MoveFailureDoubleFilingTests {
    private func makeItem() -> MenuBarItem {
        .fixture(
            tag: .appItem(bundleID: "com.example.wifi", title: "Wi-Fi"),
            windowID: 42
        )
    }

    /// The three the ledger treats as an unresponsive owner are exactly the
    /// three `move` files for itself.
    @Test("Unresponsive-owner failures are already filed")
    func unresponsiveOwnerFailuresAreAlreadyFiled() {
        let item = makeItem()
        for error in [
            MenuBarItemManager.EventError.ownerUnresponsive(item),
            .eventOperationTimeout(item),
            .itemResponseTimeout(item),
        ] {
            #expect(MenuBarItemManager.moveAlreadyFiledFailure(for: error))
        }
    }

    /// Everything else is still the caller's to file, so the backoff window
    /// keeps counting vanished items and stale destinations.
    @Test("Other failures are left for the caller to file")
    func otherFailuresAreLeftToTheCaller() {
        let item = makeItem()
        for error in [
            MenuBarItemManager.EventError.cannotComplete,
            .itemNotMovable(item),
            .missingItemBounds(item),
            .menuTrackingActive(item),
            .eventWindowMismatch(item),
            .staleDestination(item),
        ] {
            #expect(!MenuBarItemManager.moveAlreadyFiledFailure(for: error))
        }
    }

    /// An error from outside the move path — a cancellation, say — is nobody's
    /// filed failure.
    @Test("A foreign error is not treated as already filed")
    func foreignErrorIsNotAlreadyFiled() {
        #expect(!MenuBarItemManager.moveAlreadyFiledFailure(for: CancellationError()))
    }
}
