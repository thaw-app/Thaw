//
//  PollingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawConcurrency

@Suite("Polling")
struct PollingTests {
    /// Time that moves only when the poll sleeps, so no test depends on machine speed.
    final class FakeClock {
        let start = ContinuousClock.now
        lazy var now = start
        private(set) var sleeps = 0

        func sleep(_ duration: Duration) {
            now += duration
            sleeps += 1
        }
    }

    private let clock = FakeClock()

    @Test func valueOnTheFirstCheckReturnsWithoutSleeping() async {
        let value = await poll(every: .seconds(1), deadline: clock.start, now: { clock.now }, sleep: clock.sleep) { 7 }
        #expect(value == 7)
        #expect(clock.sleeps == 0)
    }

    @Test func checksEachIntervalUntilAValueArrives() async {
        let ready = clock.start + .seconds(2)
        let value = await poll(every: .seconds(1), deadline: clock.start + .seconds(5), now: { clock.now }, sleep: clock.sleep) {
            clock.now >= ready ? "ready" : nil
        }
        #expect(value == "ready")
        #expect(clock.sleeps == 2)
    }

    @Test func checkAtTheDeadlineIsTheLast() async {
        let deadline = clock.start + .seconds(2)
        var checks = 0
        let held = await pollUntil(every: .seconds(1), deadline: deadline, now: { clock.now }, sleep: clock.sleep) {
            checks += 1
            return false
        }
        #expect(!held)
        #expect(checks == 3)
        #expect(clock.now == deadline)
    }

    @Test func conditionThatHoldsAtTheDeadlineStillCounts() async {
        let deadline = clock.start + .seconds(2)
        let held = await pollUntil(every: .seconds(1), deadline: deadline, now: { clock.now }, sleep: clock.sleep) {
            clock.now >= deadline
        }
        #expect(held)
    }

    @Test func throwingSleepEndsThePoll() async {
        var checks = 0
        await #expect(throws: CancellationError.self) {
            try await pollUntil(every: .seconds(1), deadline: clock.start + .seconds(5), now: { clock.now }, sleep: { _ in
                throw CancellationError()
            }) {
                checks += 1
                return false
            }
        }
        #expect(checks == 1)
    }

    @Test func defaultSleepStopsACancelledCaller() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pollUntil(every: .seconds(1), deadline: .now + .seconds(60)) { false }
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
