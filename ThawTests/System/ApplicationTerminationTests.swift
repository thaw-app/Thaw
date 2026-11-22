//
//  ApplicationTerminationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreServices
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

/// 2026-10-22: Thaw quit at the same moment as another app while Steam ran,
/// and the log couldn't say who asked.
@Suite("The log names who asked Thaw to quit")
struct QuitRequestSourceTests {
    @Test("A quit request names who sent it", arguments: [
        (nil, nil, nil, "from Thaw itself"),
        (812, "Steam", nil, "by Steam (pid 812)"),
        (812, nil, nil, "by pid 812"),
        (42, "Thaw", nil, "from Thaw itself"),
        (98, "loginwindow", OSType(kAELogOut), "by loginwindow (pid 98), reason logo"),
    ] as [(pid_t?, String?, OSType?, String)])
    func describesTheSender(pid: pid_t?, name: String?, reason: OSType?, expected: String) {
        #expect(QuitRequestSource.describe(senderPID: pid, senderName: name, reason: reason, ownPID: 42) == expected)
    }

    @Test func fourCharCodesReadAsTheirLetters() {
        #expect(QuitRequestSource.string(fromFourCharCode: 0x7175_6974) == "quit")
    }

    /// Outside a quit event, as in a test, the request reads as Thaw's own.
    @MainActor
    @Test func theCurrentRequestOutsideAnEventIsThaws() {
        #expect(QuitRequestSource.current() == "from Thaw itself")
    }
}
