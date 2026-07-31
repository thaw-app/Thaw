//
//  MouseMovedThrottleTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import os
import Testing
@testable import Thaw

/// Characterizes `HIDEventManager.shouldProcessMouseMoved`, the time-based
/// gate that replaced a count-based "process every 5th event" throttle.
///
/// The count-based version scaled its effective processed-event rate with
/// the input device's polling rate, so a 1000 Hz mouse did roughly 8x the
/// work of a 125 Hz mouse for identical physical motion. These tests pin
/// the replacement's actual contract: the processed-event rate is bounded
/// by wall-clock time, not by how many events the device delivers.
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

    /// Regression guard for the original bug: with 1000 calls spread evenly
    /// across one simulated second (modeling a 1000 Hz device), the number
    /// processed must land near the ~30 Hz time-based cap, not near 1000 —
    /// the old counter-based throttle would have processed ~200 of these
    /// (every 5th of a 1000 Hz stream).
    @Test("A high-frequency stream is bounded by time, not event count")
    func highFrequencyStreamIsBoundedByTimeNotCount() {
        let lastProcessTime = OSAllocatedUnfairLock(initialState: TimeInterval(0))
        let interval = HIDEventManager.mouseMovedThrottleInterval

        var processedCount = 0
        for tick in 0..<1000 {
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
