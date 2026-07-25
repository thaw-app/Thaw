//
//  MouseMovedThrottleTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest
import os

/// Characterizes `HIDEventManager.shouldProcessMouseMoved`, the time-based
/// gate that replaced a count-based "process every 5th event" throttle.
///
/// The count-based version scaled its effective processed-event rate with
/// the input device's polling rate, so a 1000 Hz mouse did roughly 8x the
/// work of a 125 Hz mouse for identical physical motion. These tests pin
/// the replacement's actual contract: the processed-event rate is bounded
/// by wall-clock time, not by how many events the device delivers.
final class MouseMovedThrottleTests: XCTestCase {
    /// Two events observed at the exact same timestamp: only the first may
    /// be processed.
    func testSameTimestampOnlyProcessesOnce() {
        let lastProcessTime = OSAllocatedUnfairLock(initialState: TimeInterval(0))
        let now: TimeInterval = 100

        XCTAssertTrue(HIDEventManager.shouldProcessMouseMoved(now: now, lastProcessTime: lastProcessTime))
        XCTAssertFalse(HIDEventManager.shouldProcessMouseMoved(now: now, lastProcessTime: lastProcessTime))
    }

    /// An event exactly one throttle interval after the last processed
    /// event is processed.
    func testFullIntervalLaterProcesses() {
        let lastProcessTime = OSAllocatedUnfairLock(initialState: TimeInterval(0))
        let interval = HIDEventManager.mouseMovedThrottleInterval
        let first: TimeInterval = 100
        let second = first + interval

        XCTAssertTrue(HIDEventManager.shouldProcessMouseMoved(now: first, lastProcessTime: lastProcessTime))
        XCTAssertTrue(HIDEventManager.shouldProcessMouseMoved(now: second, lastProcessTime: lastProcessTime))
    }

    /// An event only half an interval after the last processed event is
    /// dropped.
    func testHalfIntervalLaterDoesNotProcess() {
        let lastProcessTime = OSAllocatedUnfairLock(initialState: TimeInterval(0))
        let interval = HIDEventManager.mouseMovedThrottleInterval
        let first: TimeInterval = 100
        let second = first + (interval / 2)

        XCTAssertTrue(HIDEventManager.shouldProcessMouseMoved(now: first, lastProcessTime: lastProcessTime))
        XCTAssertFalse(HIDEventManager.shouldProcessMouseMoved(now: second, lastProcessTime: lastProcessTime))
    }

    /// Regression guard for the original bug: with 1000 calls spread evenly
    /// across one simulated second (modeling a 1000 Hz device), the number
    /// processed must land near the ~30 Hz time-based cap, not near 1000 —
    /// the old counter-based throttle would have processed ~200 of these
    /// (every 5th of a 1000 Hz stream).
    func testHighFrequencyStreamIsBoundedByTimeNotCount() {
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
        XCTAssertLessThanOrEqual(processedCount, expectedMax)
        XCTAssertGreaterThan(processedCount, 0)
    }
}
