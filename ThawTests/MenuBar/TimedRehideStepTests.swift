//
//  TimedRehideStepTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Timed rehide countdown")
struct TimedRehideStepTests {
    @Test("With the pointer outside the bars and no countdown, one starts, so a reveal with no movement still rehides")
    func startsWithoutMovement() {
        #expect(TimedRehideStep.next(pointerInBar: false, countdownRunning: false) == .start)
    }

    @Test("A running countdown is left alone while the pointer stays outside")
    func keepsRunning() {
        #expect(TimedRehideStep.next(pointerInBar: false, countdownRunning: true) == .keep)
    }

    @Test("The pointer in either bar stops the countdown", arguments: [false, true])
    func cancelsInBar(running: Bool) {
        #expect(TimedRehideStep.next(pointerInBar: true, countdownRunning: running) == .cancel)
    }
}
