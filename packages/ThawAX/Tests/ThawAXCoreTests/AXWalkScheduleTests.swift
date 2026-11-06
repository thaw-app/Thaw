//
//  AXWalkScheduleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Synchronization
import Testing
@testable import ThawAXCore

@Suite("AX walk schedule")
struct AXWalkScheduleTests {
    @Test("Deferred apps go after the others, each group keeping its order")
    func deferredGoLast() {
        let ordered = AXWalkSchedule.ordered([1, 2, 3, 4, 5]) { $0.isMultiple(of: 2) }
        #expect(ordered == [1, 3, 5, 2, 4])
    }

    @Test("No more than the limit run at once, and results come back in input order")
    func boundedMapKeepsOrder() {
        let state = Mutex((current: 0, peak: 0))
        let results = AXWalkSchedule.map(20, limit: 4) { index in
            state.withLock {
                $0.current += 1
                $0.peak = max($0.peak, $0.current)
            }
            Thread.sleep(forTimeInterval: 0.01)
            state.withLock { $0.current -= 1 }
            return index * 2
        }
        #expect(results == (0 ..< 20).map { $0 * 2 })
        #expect(state.withLock { $0.peak } <= 4)
        #expect(state.withLock { $0.peak } > 1)
    }

    /// The helper read 117 apps one after another, about two seconds on a busy Mac.
    @Test("A hundred reads of 10 ms each finish in a fraction of the time one after another would take")
    func parallelWalkIsFaster() {
        let start = Date()
        _ = AXWalkSchedule.map(100, limit: AXWalkSchedule.concurrency) { _ in
            Thread.sleep(forTimeInterval: 0.01)
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.9, "one after another this can't take less than 1 s; took \(elapsed) s")
    }

    @Test("Nothing to read returns nothing")
    func emptyMap() {
        #expect(AXWalkSchedule.map(0, limit: 8) { $0 }.isEmpty)
    }
}
