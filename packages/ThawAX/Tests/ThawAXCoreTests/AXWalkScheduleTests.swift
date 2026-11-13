//
//  AXWalkScheduleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Dispatch
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

    /// The first batch must overlap; a busy runner must not fail for taking longer to schedule it.
    @Test("The default walk starts a full batch before any of its reads finish")
    func defaultWalkStartsAFullBatch() {
        let width = AXWalkSchedule.concurrency
        let entered = Mutex(0)
        let timedOut = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let results = AXWalkSchedule.map(100, limit: width) { index in
            if index < width {
                let allEntered = entered.withLock { count in
                    count += 1
                    return count == width
                }
                if allEntered {
                    for _ in 0 ..< width { release.signal() }
                }
                // A safety bound releases the other reads even if the scheduler regresses to serial.
                if release.wait(timeout: .now() + .seconds(60)) == .timedOut {
                    timedOut.withLock { $0 = true }
                    for _ in 0 ..< width { release.signal() }
                }
            }
            return index
        }
        #expect(!timedOut.withLock { $0 }, "the whole first batch must enter before any read can return")
        #expect(results == Array(0 ..< 100))
    }

    @Test("Nothing to read returns nothing")
    func emptyMap() {
        #expect(AXWalkSchedule.map(0, limit: 8) { $0 }.isEmpty)
    }
}
