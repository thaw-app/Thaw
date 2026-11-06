//
//  MoveOperationTrackerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Move operation tracker")
@MainActor
struct MoveOperationTrackerTests {
    @Test("A fresh tracker reports nothing")
    func freshTrackerIsQuiet() {
        let tracker = MoveOperationTracker()
        #expect(!tracker.occurred(within: .seconds(60)))
        #expect(!tracker.isInFlight)
        #expect(tracker.lastInstant == nil)
    }

    @Test("A stamp counts as recent without stamping an in-flight window")
    func stampIsRecent() {
        let tracker = MoveOperationTracker()
        tracker.noteMoveOperation()
        #expect(tracker.occurred(within: .seconds(1)))
        #expect(!tracker.isInFlight)
    }

    @Test("An in-flight move counts as recent for the whole window, even unstamped")
    func inFlightCountsAsRecent() {
        let tracker = MoveOperationTracker()
        tracker.beginMoveOperation()
        #expect(tracker.isInFlight)
        #expect(tracker.occurred(within: .zero))
        // Begin does not stamp: consumers computing buffers off the last
        // stamp must not see a phantom operation.
        #expect(tracker.lastInstant == nil)
        tracker.endMoveOperation()
        #expect(!tracker.isInFlight)
        #expect(!tracker.occurred(within: .seconds(60)))
    }

    @Test("Nested begins stay in flight until every end")
    func nestedBegins() {
        let tracker = MoveOperationTracker()
        tracker.beginMoveOperation()
        tracker.beginMoveOperation()
        tracker.endMoveOperation()
        #expect(tracker.isInFlight)
        tracker.endMoveOperation()
        #expect(!tracker.isInFlight)
        // An unbalanced end never goes negative and never blocks a later begin.
        tracker.endMoveOperation()
        tracker.beginMoveOperation()
        #expect(tracker.isInFlight)
    }

    @Test("Waiting returns only after the move in flight ends")
    func waitUntilIdleWaitsForTheMove() async {
        let tracker = MoveOperationTracker()
        tracker.beginMoveOperation()
        var returned = false
        let waiter = Task {
            await tracker.waitUntilIdle(pollingEvery: .milliseconds(5))
            returned = true
        }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!returned)
        tracker.endMoveOperation()
        await waiter.value
        #expect(returned)
    }
}
