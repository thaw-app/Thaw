//
//  ApplicationTerminationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Application termination")
@MainActor
struct ApplicationTerminationTests {
    @Test("The request schedules termination instead of terminating inline")
    func requestSchedulesTheTermination() {
        var scheduledActions: [() -> Void] = []
        var terminateCalls = 0

        ApplicationTermination.request(
            schedule: { action in scheduledActions.append(action) },
            terminate: { terminateCalls += 1 }
        )

        // Nothing terminates synchronously: applicationShouldTerminate gets
        // to finish its asynchronous cleanup first.
        #expect(terminateCalls == 0)
        #expect(scheduledActions.count == 1)

        // Once the run loop unwinds, the scheduled action terminates.
        scheduledActions.forEach { $0() }
        #expect(terminateCalls == 1)
    }

    @Test("Each request schedules its own termination")
    func everyRequestSchedules() {
        var scheduledActions: [() -> Void] = []
        var terminateCalls = 0

        ApplicationTermination.request(
            schedule: { action in scheduledActions.append(action) },
            terminate: { terminateCalls += 1 }
        )
        ApplicationTermination.request(
            schedule: { action in scheduledActions.append(action) },
            terminate: { terminateCalls += 1 }
        )

        #expect(scheduledActions.count == 2)
        #expect(terminateCalls == 0)

        scheduledActions.forEach { $0() }
        #expect(terminateCalls == 2)
    }
}
