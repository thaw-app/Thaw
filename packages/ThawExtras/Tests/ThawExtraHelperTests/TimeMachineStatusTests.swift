//
//  TimeMachineStatusTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawExtraHelper

@Suite("Time Machine status")
struct TimeMachineStatusTests {
    @Test("Idle output reads as not running, with no percentage")
    func idle() {
        let output = """
        Backup session status:
        {
            ClientID = "com.apple.backupd";
            Percent = "-1";
            Running = 0;
        }
        """
        #expect(TimeMachineStatus.parse(output) == .idle)
    }

    @Test("A backup in progress reads as running with its fraction done")
    func running() {
        let output = """
        Backup session status:
        {
            BackupPhase = Copying;
            ClientID = "com.apple.backupd";
            Percent = "0.42";
            Progress =     {
                Percent = "0.42";
                TimeRemaining = 120;
            };
            Running = 1;
            Stopping = 0;
        }
        """
        #expect(TimeMachineStatus.parse(output) == TimeMachineStatus(isRunning: true, fraction: 0.42))
    }

    @Test("A backup that hasn't started copying has no fraction yet")
    func preparing() {
        let output = "{\n    BackupPhase = Starting;\n    Percent = \"-1\";\n    Running = 1;\n}"
        #expect(TimeMachineStatus.parse(output) == TimeMachineStatus(isRunning: true, fraction: nil))
    }

    @Test("Empty output, from tmutil failing, reads as idle")
    func failure() {
        #expect(TimeMachineStatus.parse("") == .idle)
    }

    @Test("The stand-in shows unless Thaw hides it, and only during a backup when asked", arguments: [
        (false, false, false, true),
        (false, true, false, false),
        (false, true, true, true),
        (true, false, true, false),
        (true, true, true, false),
    ])
    func visibility(hiddenByThaw: Bool, onlyWhileBackingUp: Bool, isRunning: Bool, shows: Bool) {
        #expect(TimeMachineStatus.showsItem(hiddenByThaw: hiddenByThaw, onlyWhileBackingUp: onlyWhileBackingUp, isRunning: isRunning) == shows)
    }
}

@MainActor
@Suite("Time Machine icon")
struct TimeMachineIconTests {
    @Test("The spinning icon has twelve template frames of the same size")
    func frames() {
        let frames = TimeMachineExtra.spinFrames(symbolName: "clock.arrow.trianglehead.counterclockwise.rotate.90", label: "Time Machine")
        #expect(frames.count == 12)
        let allTemplates = frames.allSatisfy(\.isTemplate)
        let sizes = Set(frames.map { "\($0.size)" })
        #expect(allTemplates)
        #expect(sizes.count == 1)
    }
}

@Suite("Time Machine checks")
struct TimeMachinePollTests {
    @Test("Idle checks are spaced out, running ones close together")
    func intervals() {
        #expect(TimeMachineStatus.pollInterval(isRunning: false, isHiddenByThaw: false, areScreensAsleep: false) == .seconds(30))
        #expect(TimeMachineStatus.pollInterval(isRunning: true, isHiddenByThaw: false, areScreensAsleep: false) == .seconds(3))
    }

    @Test("Nothing is checked while Thaw hides the stand-in or the screens sleep", arguments: [(true, false), (false, true), (true, true)])
    func paused(hiddenByThaw: Bool, asleep: Bool) {
        #expect(TimeMachineStatus.pollInterval(isRunning: true, isHiddenByThaw: hiddenByThaw, areScreensAsleep: asleep) == nil)
    }
}

@Suite("Time Machine status read", .timeLimit(.minutes(1)))
struct TimeMachineStatusReadTests {
    @Test("A command that answers in time returns its output")
    func answersInTime() async {
        let output = await CommandOutput.output(
            of: URL(filePath: "/bin/echo"), arguments: ["Running = 0;"], timeout: .seconds(5)
        )
        #expect(output == "Running = 0;\n")
    }

    @Test("A command that hangs is ended at the timeout and reads as no output")
    func hangIsCutOff() async {
        let start = ContinuousClock.now
        let output = await CommandOutput.output(
            of: URL(filePath: "/bin/sleep"), arguments: ["30"], timeout: .milliseconds(200)
        )
        #expect(output.isEmpty)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test(
        "A command that ignores SIGTERM or leaves its output open still ends near the timeout",
        arguments: ["trap '' TERM; sleep 30", "sleep 30 & echo started"]
    )
    func timeoutHolds(script: String) async {
        let start = ContinuousClock.now
        let output = await CommandOutput.output(
            of: URL(filePath: "/bin/sh"), arguments: ["-c", script], timeout: .milliseconds(200)
        )
        #expect(output.isEmpty)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("A command that can't start reads as no output")
    func missingCommand() async {
        let output = await CommandOutput.output(
            of: URL(filePath: "/nonexistent/tmutil"), arguments: [], timeout: .seconds(1)
        )
        #expect(output.isEmpty)
    }
}
