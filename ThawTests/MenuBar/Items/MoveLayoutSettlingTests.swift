//
//  MoveLayoutSettlingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// The polling loop behind `waitForLayoutToSettle`: a landing is judged
/// only once two consecutive readings of the bar agree, and never later
/// than the poll budget.
@Suite("Move layout settling")
struct MoveLayoutSettlingTests {
    @Test("Only a requested final refresh evaluates an unchanged cache for persistence")
    func validatedMoveCanPersistUnchangedCache() {
        #expect(!MenuBarItemManager.shouldEvaluateSavedOrderPersistence(
            cacheChanged: false,
            forcePersistSavedOrder: false
        ))
        #expect(MenuBarItemManager.shouldEvaluateSavedOrderPersistence(
            cacheChanged: false,
            forcePersistSavedOrder: true
        ))
        #expect(MenuBarItemManager.shouldEvaluateSavedOrderPersistence(
            cacheChanged: true,
            forcePersistSavedOrder: false
        ))
    }

    @Test("A dropped cache attempt cannot report a completed cycle")
    @MainActor
    func droppedCacheAttemptIsIncomplete() {
        let attempt = MenuBarItemManager.CacheAttempt()

        attempt.recordCompletion(cyclesAtEntry: 12, cyclesAtExit: 12)

        #expect(!attempt.didCompleteCycle)
    }

    @Test("An accepted cache attempt reports its own completed cycle")
    @MainActor
    func acceptedCacheAttemptCompletes() {
        let attempt = MenuBarItemManager.CacheAttempt()

        attempt.recordCompletion(cyclesAtEntry: 12, cyclesAtExit: 13)

        #expect(attempt.didCompleteCycle)
    }

    @Test("A cache attempt invalidated by a later move remains incomplete")
    @MainActor
    func movedAfterCacheAttemptIsIncomplete() {
        let attempt = MenuBarItemManager.CacheAttempt()

        attempt.recordCompletion(
            cyclesAtEntry: 12,
            cyclesAtExit: 13,
            snapshotRemainedCurrent: false
        )

        #expect(!attempt.didCompleteCycle)
    }

    @Test("A fast layout refresh keeps the cached identity and fresh geometry")
    func fastRefreshReusesCachedIdentity() {
        let windowID: CGWindowID = 711
        let cached = MenuBarItem.fixture(
            tag: .appItem(
                bundleID: "com.example.status-item",
                title: "Item-0",
                windowID: windowID
            ),
            windowID: windowID,
            bounds: CGRect(x: 1400, y: 0, width: 24, height: 33),
            sourcePID: 4321,
            ownerPID: 99,
            title: "Item-0"
        )
        let freshGeometry = MenuBarItem.fixture(
            tag: .appItem(
                bundleID: "com.apple.controlcenter",
                title: "Item-0",
                windowID: windowID
            ),
            windowID: windowID,
            bounds: CGRect(x: -3700, y: 0, width: 24, height: 33),
            sourcePID: nil,
            ownerPID: 99,
            title: "Item-0",
            isOnScreen: false
        )

        let refreshed = MenuBarItemManager.reusingCachedIdentities(
            in: [freshGeometry],
            from: [cached]
        )

        #expect(refreshed.count == 1)
        #expect(refreshed[0].tag == cached.tag)
        #expect(refreshed[0].sourcePID == cached.sourcePID)
        #expect(refreshed[0].bounds == freshGeometry.bounds)
        #expect(!refreshed[0].isOnScreen)
    }

    @Test("A recycled window from another owner does not inherit cached identity")
    func recycledWindowDoesNotReuseCachedIdentity() {
        let cached = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.old", title: "Item-0", windowID: 711),
            windowID: 711,
            sourcePID: 4321,
            ownerPID: 99,
            title: "Item-0"
        )
        let replacement = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.apple.controlcenter", title: "Item-0", windowID: 711),
            windowID: 711,
            sourcePID: nil,
            ownerPID: 100,
            title: "Item-0"
        )

        let refreshed = MenuBarItemManager.reusingCachedIdentities(
            in: [replacement],
            from: [cached]
        )

        #expect(refreshed == [replacement])
    }

    @Test("Two matching consecutive readings settle the value")
    func settlesOnTheFirstRepeat() async {
        let values = [1465, 1445, 1427, 1427, 1400]
        var index = 0
        var waits = 0

        let outcome = await MenuBarItemManager.settledReading(
            maxPolls: 10,
            read: {
                defer { index += 1 }
                return values[index]
            },
            wait: { waits += 1 }
        )

        #expect(outcome.settled)
        #expect(outcome.value == 1427)
        #expect(index == 4)
        #expect(waits == 3)
    }

    @Test("A bar that keeps moving gives up after the poll budget")
    func givesUpAfterTheBudget() async {
        var next = 0

        let outcome = await MenuBarItemManager.settledReading(
            maxPolls: 4,
            read: {
                next += 1
                return next
            },
            wait: {}
        )

        #expect(!outcome.settled)
        #expect(outcome.value == 4)
    }

    @Test("A single-poll budget returns the first reading unconfirmed")
    func singlePollIsUnconfirmed() async {
        var waits = 0

        let outcome = await MenuBarItemManager.settledReading(
            maxPolls: 1,
            read: { "only" },
            wait: { waits += 1 }
        )

        #expect(!outcome.settled)
        #expect(outcome.value == "only")
        #expect(waits == 0)
    }
}
