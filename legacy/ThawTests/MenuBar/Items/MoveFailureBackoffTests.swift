//
//  MoveFailureBackoffTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Per-item backoff so one unmovable item (a vanished Control Center window, a
/// hung owner) does not re-trigger a cursor-hijacking apply every cache cycle (#736).
@Suite("Move failure backoff")
struct MoveFailureBackoffTests {
    @Test("The interval grows with the failure count")
    func intervalGrowsWithFailureCount() {
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 1) == .seconds(30))
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 2) == .seconds(60))
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 4) == .seconds(120))
    }

    /// Capped so an item that recovers does not wait unboundedly for its next attempt.
    @Test("The interval is capped at five minutes")
    func intervalIsCappedAtFiveMinutes() {
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 10) == .seconds(300))
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 1000) == .seconds(300))
    }

    /// A zero or negative count is treated as one failure.
    @Test("A non-positive count clamps to a single failure")
    func nonPositiveCountClampsToSingleFailure() {
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: 0) == .seconds(30))
        #expect(MenuBarItemManager.moveFailureBackoffInterval(failureCount: -3) == .seconds(30))
    }
}

/// Which failures `move` has already filed with the ledger when it throws, so a
/// catch clause does not charge one failed move twice.
///
/// Double-filing consumed both halves of "wait for another failure before
/// marking" at once: 1Password was marked unresponsive a millisecond after
/// the log said it was waiting for a second failure (#687).
@Suite("Move failure double filing")
struct MoveFailureDoubleFilingTests {
    private func makeItem() -> MenuBarItem {
        .fixture(
            tag: .appItem(bundleID: "com.example.wifi", title: "Wi-Fi"),
            windowID: 42
        )
    }

    /// The three unresponsive-owner failures are exactly the three `move` files itself.
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

    /// Everything else is the caller's to file, so backoff still counts vanished
    /// items and stale destinations.
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

    /// An error from outside the move path, such as cancellation, is nobody's filed failure.
    @Test("A foreign error is not treated as already filed")
    func foreignErrorIsNotAlreadyFiled() {
        #expect(!MenuBarItemManager.moveAlreadyFiledFailure(for: CancellationError()))
    }
}
