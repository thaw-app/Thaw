//
//  MenuBarItemManagerSignatureGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Verifies the stability gate that keeps a transient macOS 27 menu-bar
/// enumeration blip from triggering a full recache + assertion re-apply — the
/// recache → `applySavedLayout` → preferred-position rewrite that visibly
/// reorders icons ("items keep moving on their own"). A differing signature must
/// hold, unchanged, for the whole grace window before it confirms.
@MainActor
final class MenuBarItemManagerSignatureGateTests: XCTestCase {
    private let cached = ["A", "B"]
    private let grace: Duration = .seconds(3)

    private func decide(
        current: [String],
        pending: [String]?,
        firstSeen: ContinuousClock.Instant?,
        now: ContinuousClock.Instant
    ) -> (recache: Bool, newPending: [String]?, newFirstSeen: ContinuousClock.Instant?) {
        MenuBarItemManager.signatureRecacheDecision(
            cached: cached,
            current: current,
            pending: pending,
            firstSeen: firstSeen,
            now: now,
            grace: grace
        )
    }

    func testUnchangedSignatureNeverRecachesAndClearsPending() {
        let now = ContinuousClock.now
        let decision = decide(
            current: cached,
            pending: ["A", "B", "C"], // a stale candidate
            firstSeen: now - .seconds(10), // even a long-standing one
            now: now
        )
        XCTAssertFalse(decision.recache)
        XCTAssertNil(decision.newPending)
        XCTAssertNil(decision.newFirstSeen)
    }

    func testFirstDifferenceDefersAndStartsClock() {
        let now = ContinuousClock.now
        let current = ["A", "B", "C"]
        let decision = decide(current: current, pending: nil, firstSeen: nil, now: now)
        XCTAssertFalse(decision.recache, "A first-seen difference must not recache")
        XCTAssertEqual(decision.newPending, current)
        XCTAssertEqual(decision.newFirstSeen, now, "The grace clock starts now")
    }

    func testDifferenceWithinGraceKeepsDeferringAndPreservesClockStart() {
        let start = ContinuousClock.now
        let current = ["A", "B", "C"]
        // Same difference seen again, but only partway through the grace window.
        let decision = decide(
            current: current,
            pending: current,
            firstSeen: start,
            now: start + .seconds(1)
        )
        XCTAssertFalse(decision.recache, "Still inside the grace window")
        XCTAssertEqual(decision.newPending, current)
        XCTAssertEqual(
            decision.newFirstSeen,
            start,
            "The streak start is preserved so the window measures continuous persistence"
        )
    }

    func testDifferenceHeldPastGraceConfirmsAndRecaches() {
        let start = ContinuousClock.now
        let current = ["A", "B", "C"]
        let decision = decide(
            current: current,
            pending: current,
            firstSeen: start,
            now: start + grace // grace has fully elapsed
        )
        XCTAssertTrue(decision.recache)
        XCTAssertNil(decision.newPending, "Gate resets after confirming")
        XCTAssertNil(decision.newFirstSeen)
    }

    func testChangedDifferenceRestartsClock() {
        // First an extra item, then a *different* extra item: the difference
        // itself changed, so the streak restarts — exactly the transient flicker
        // we want to swallow, even if each blip lingers.
        let start = ContinuousClock.now
        let later = start + .seconds(2)
        let decision = decide(
            current: ["A", "B", "D"],
            pending: ["A", "B", "C"],
            firstSeen: start,
            now: later
        )
        XCTAssertFalse(decision.recache, "A changed difference must re-defer, not recache")
        XCTAssertEqual(decision.newPending, ["A", "B", "D"])
        XCTAssertEqual(decision.newFirstSeen, later, "Clock restarts on the new difference")
    }

    func testTransientDropThatRevertsNeverRecaches() {
        // Item C drops from enumeration (still physically present), then returns
        // before the grace elapses. The gate must never fire a recache.
        let cachedFull = ["A", "B", "C"]
        let start = ContinuousClock.now

        // Drop observed: C missing.
        let dropped = MenuBarItemManager.signatureRecacheDecision(
            cached: cachedFull,
            current: ["A", "B"],
            pending: nil,
            firstSeen: nil,
            now: start,
            grace: grace
        )
        XCTAssertFalse(dropped.recache)
        XCTAssertEqual(dropped.newPending, ["A", "B"])

        // C returns within the grace window: current matches the cache again.
        let returned = MenuBarItemManager.signatureRecacheDecision(
            cached: cachedFull,
            current: cachedFull,
            pending: dropped.newPending,
            firstSeen: dropped.newFirstSeen,
            now: start + .seconds(1),
            grace: grace
        )
        XCTAssertFalse(returned.recache, "A drop that reverts within grace must not recache")
        XCTAssertNil(returned.newPending, "Gate clears once live state matches the cache")
        XCTAssertNil(returned.newFirstSeen)
    }
}
