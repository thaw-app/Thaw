//
//  ControlItemRecoveryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Characterizes the bounded control-item recovery path for issue #754:
/// on macOS 26 with multiple displays, after long uptime `ControlItemPair`
/// lookup in `cacheItemsRegardless` can start failing permanently. These
/// tests cover the pure escalation decision that gates rebuilding the
/// control items' underlying status items.
///
/// The detector re-arming half of the fix (a failed lookup no longer commits
/// `itemWindowIDs` to `CacheActor`, so `cacheItemsIfNeeded` keeps seeing a
/// mismatch and keeps re-driving recache attempts) is not covered here:
/// `CacheActor` is a private nested type of `MenuBarItemManager` with no
/// reachable seam, and exercising it live would require a real
/// `MenuBarItemManager` wired to an `AppState`, live `NSStatusItem`s, and
/// screen-recording permission — not available in this unit test target.
/// That half is verified by code reading instead: see the ordering of
/// `cacheActor.updateCachedItemWindowIDs`/`updateCachedCloneWindowIDs` in
/// `cacheItemsRegardless`, which now runs only after the `ControlItemPair`
/// guard succeeds, never inside the failure branch.
final class ControlItemRecoveryTests: XCTestCase {
    func testBelowThresholdDoesNotRebuild() {
        for count in 0 ..< MenuBarItemManager.controlItemRebuildThreshold {
            XCTAssertFalse(
                MenuBarItemManager.shouldRebuildControlItems(consecutiveFailures: count),
                "consecutiveFailures=\(count) should not yet trigger a rebuild"
            )
        }
    }

    func testThresholdTriggersRebuild() {
        XCTAssertTrue(
            MenuBarItemManager.shouldRebuildControlItems(
                consecutiveFailures: MenuBarItemManager.controlItemRebuildThreshold
            )
        )
    }

    func testBeyondThresholdStillTriggersRebuild() {
        XCTAssertTrue(
            MenuBarItemManager.shouldRebuildControlItems(
                consecutiveFailures: MenuBarItemManager.controlItemRebuildThreshold + 5
            )
        )
    }

    func testCustomThresholdIsRespected() {
        XCTAssertFalse(MenuBarItemManager.shouldRebuildControlItems(consecutiveFailures: 1, threshold: 2))
        XCTAssertTrue(MenuBarItemManager.shouldRebuildControlItems(consecutiveFailures: 2, threshold: 2))
    }

    /// Models the manager's own counter usage: increments on failure, reset
    /// to zero on success and immediately after a rebuild fires, so a
    /// rebuild happens at most once per failure streak.
    func testCounterResetPreventsRepeatRebuildsWithinAStreak() {
        var consecutiveFailures = 0
        var rebuildCount = 0

        func recordFailure() {
            consecutiveFailures += 1
            if MenuBarItemManager.shouldRebuildControlItems(consecutiveFailures: consecutiveFailures) {
                rebuildCount += 1
                consecutiveFailures = 0
            }
        }

        for _ in 0 ..< (MenuBarItemManager.controlItemRebuildThreshold * 3) {
            recordFailure()
        }

        XCTAssertEqual(rebuildCount, 3)
    }
}
