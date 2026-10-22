//
//  IconShadeReadScheduleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("When the overlay reads the icons' shade")
struct IconShadeReadScheduleTests {
    /// Runs each step on one schedule and returns what each answered.
    private func answers(_ steps: [(inout IconShadeReadSchedule) -> Bool]) -> [Bool] {
        var schedule = IconShadeReadSchedule()
        return steps.map { $0(&schedule) }
    }

    private func start(force: Bool, hasShade: Bool) -> (inout IconShadeReadSchedule) -> Bool {
        { $0.shouldStart(force: force, hasShade: hasShade) }
    }

    private func finish(found: Bool) -> (inout IconShadeReadSchedule) -> Bool {
        { $0.finish(found: found) }
    }

    @Test("An unknown shade is read once at a time, and a known one only on a bar change")
    func oneReadAtATime() {
        let result = answers([
            start(force: false, hasShade: false),
            start(force: false, hasShade: false),
            finish(found: true),
            start(force: false, hasShade: true),
            start(force: true, hasShade: true),
        ])
        #expect(result == [true, false, false, false, true])
    }

    @Test("A bar change during a read gets a read of its own once that one ends")
    func barChangeDuringRead() {
        let result = answers([
            start(force: false, hasShade: false),
            start(force: true, hasShade: false),
            finish(found: true),
            start(force: true, hasShade: true),
            finish(found: true),
        ])
        #expect(result == [true, false, true, true, false])
    }

    @Test("After a read finds nothing, only a bar change reads again")
    func failedReadWaitsForBarChange() {
        let result = answers([
            start(force: false, hasShade: false),
            finish(found: false),
            start(force: false, hasShade: false),
            start(force: true, hasShade: false),
            finish(found: true),
            { !$0.isReading },
        ])
        #expect(result == [true, false, false, true, false, true])
    }

    @Test("A cancelled read is forgotten")
    func resetForgetsTheRead() {
        let result = answers([
            start(force: false, hasShade: false),
            start(force: true, hasShade: false),
            { schedule in
                schedule.reset()
                return !schedule.isReading
            },
            start(force: false, hasShade: false),
            finish(found: true),
        ])
        #expect(result == [true, false, true, true, false])
    }
}
