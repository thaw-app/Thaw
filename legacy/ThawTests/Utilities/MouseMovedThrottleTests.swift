//
//  MouseMovedThrottleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import os
import Testing
@testable import Thaw

/// Characterizes `HIDEventManager.shouldProcessMouseMoved`, a time-based
/// gate: the processed-event rate is bounded by wall-clock time, not by the
/// device's polling rate. A count-based "every 5th event" throttle made a
/// 1000 Hz mouse do about 8x the work of a 125 Hz one.
@Suite("Mouse moved throttle")
struct MouseMovedThrottleTests {
    /// Two events observed at the exact same timestamp: only the first may
    /// be processed.
    @Test("Two events at the same timestamp process only once")
    func sameTimestampOnlyProcessesOnce() {
        let lastProcessTime = OSAllocatedUnfairLock(initialState: TimeInterval(0))
        let now: TimeInterval = 100

        #expect(HIDEventManager.shouldProcessMouseMoved(now: now, lastProcessTime: lastProcessTime))
        #expect(!HIDEventManager.shouldProcessMouseMoved(now: now, lastProcessTime: lastProcessTime))
    }

    /// An event exactly one throttle interval after the last processed
    /// event is processed.
    @Test("An event a full interval later is processed")
    func fullIntervalLaterProcesses() {
        let lastProcessTime = OSAllocatedUnfairLock(initialState: TimeInterval(0))
        let interval = HIDEventManager.mouseMovedThrottleInterval
        let first: TimeInterval = 100
        // `first + interval` does not round-trip: the interval is 1/30, and
        // adding it to a timestamp of this magnitude drops low bits that
        // subtracting `first` back out cannot recover, leaving the difference
        // a couple of femtoseconds *under* one interval. Step to the next
        // representable value so "one interval later" is actually expressible.
        // A strict `>` in the gate still fails this, which is the regression
        // the test is here to catch.
        let second = (first + interval).nextUp

        #expect(HIDEventManager.shouldProcessMouseMoved(now: first, lastProcessTime: lastProcessTime))
        #expect(HIDEventManager.shouldProcessMouseMoved(now: second, lastProcessTime: lastProcessTime))
    }

    /// An event only half an interval after the last processed event is
    /// dropped.
    @Test("An event half an interval later is dropped")
    func halfIntervalLaterDoesNotProcess() {
        let lastProcessTime = OSAllocatedUnfairLock(initialState: TimeInterval(0))
        let interval = HIDEventManager.mouseMovedThrottleInterval
        let first: TimeInterval = 100
        let second = first + (interval / 2)

        #expect(HIDEventManager.shouldProcessMouseMoved(now: first, lastProcessTime: lastProcessTime))
        #expect(!HIDEventManager.shouldProcessMouseMoved(now: second, lastProcessTime: lastProcessTime))
    }

    /// Regression guard: 1000 calls spread across one simulated second (a
    /// 1000 Hz device) must land near the ~30 Hz cap, not near the ~200 the
    /// old every-5th-event throttle processed.
    @Test("A high-frequency stream is bounded by time, not event count")
    func highFrequencyStreamIsBoundedByTimeNotCount() {
        let lastProcessTime = OSAllocatedUnfairLock(initialState: TimeInterval(0))
        let interval = HIDEventManager.mouseMovedThrottleInterval

        var processedCount = 0
        for tick in 0 ..< 1000 {
            let now = TimeInterval(tick) / 1000
            if HIDEventManager.shouldProcessMouseMoved(now: now, lastProcessTime: lastProcessTime) {
                processedCount += 1
            }
        }

        let expectedMax = Int((1.0 / interval).rounded(.up)) + 1
        #expect(processedCount <= expectedMax)
        #expect(processedCount > 0)
    }
}
