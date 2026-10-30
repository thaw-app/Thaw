//
//  ApplicationTerminationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// When a quit request reaches the app. Termination is a recorder here; nothing quits.
@MainActor
@Suite("Application termination")
struct ApplicationTerminationTests {
    private final class Recorder {
        var terminations = 0
        var scheduled: [@MainActor () -> Void] = []
    }

    @Test("A request hands termination to the scheduler instead of quitting at once")
    func requestDefersToTheScheduler() throws {
        let recorder = Recorder()

        ApplicationTermination.request(
            schedule: { recorder.scheduled.append($0) },
            terminate: { recorder.terminations += 1 }
        )

        #expect(recorder.terminations == 0)
        let scheduled = try #require(recorder.scheduled.first)
        #expect(recorder.scheduled.count == 1)
        scheduled()
        #expect(recorder.terminations == 1)
    }

    @Test("The default scheduler runs the action on a later turn of the main run loop")
    func defaultSchedulerRunsLater() async {
        let recorder = Recorder()

        ApplicationTermination.scheduleOnDefaultRunLoop { recorder.terminations += 1 }

        #expect(recorder.terminations == 0, "the action waits for the current run loop pass to unwind")
        let deadline = ContinuousClock.now + .seconds(10)
        while recorder.terminations == 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(recorder.terminations == 1)
    }
}
