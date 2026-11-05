//
//  TimeMachineStatusReadTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawExtraHelper

@Suite("Time Machine status read", .timeLimit(.minutes(1)))
struct TimeMachineStatusReadTests {
    @Test("A command that answers in time returns its output")
    func answersInTime() async {
        let output = await TimeMachineExtra.output(
            of: URL(filePath: "/bin/echo"), arguments: ["Running = 0;"], timeout: .seconds(5)
        )
        #expect(output == "Running = 0;\n")
    }

    @Test("A command that hangs is ended at the timeout and reads as no output")
    func hangIsCutOff() async {
        let start = ContinuousClock.now
        let output = await TimeMachineExtra.output(
            of: URL(filePath: "/bin/sleep"), arguments: ["30"], timeout: .milliseconds(200)
        )
        #expect(output.isEmpty)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test("A command that can't start reads as no output")
    func missingCommand() async {
        let output = await TimeMachineExtra.output(
            of: URL(filePath: "/nonexistent/tmutil"), arguments: [], timeout: .seconds(1)
        )
        #expect(output.isEmpty)
    }
}
