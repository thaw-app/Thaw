//
//  OwnerLivenessGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Owner liveness gate")
struct OwnerLivenessGateTests {
    private let start = ContinuousClock.now

    private func gate(readAt instant: ContinuousClock.Instant, signature: Int = 1) -> OwnerLivenessGate<Int> {
        var gate = OwnerLivenessGate<Int>()
        gate.noteRead(signature: signature, at: instant)
        return gate
    }

    @Test("The first check reads the process table")
    func firstCheckReads() {
        #expect(OwnerLivenessGate<Int>().isReadDue(ownersAlive: true, signature: 1, now: start))
    }

    @Test("Nothing changed since the last read, so the next check skips it")
    func unchangedSkips() {
        let gate = gate(readAt: start)
        #expect(!gate.isReadDue(ownersAlive: true, signature: 1, now: start.advanced(by: .seconds(3))))
    }

    @Test("A cached owner whose process is gone forces a read")
    func deadOwnerReads() {
        let gate = gate(readAt: start)
        #expect(gate.isReadDue(ownersAlive: false, signature: 1, now: start.advanced(by: .seconds(3))))
    }

    @Test("A different list of running apps forces a read")
    func changedListReads() {
        let gate = gate(readAt: start)
        #expect(gate.isReadDue(ownersAlive: true, signature: 2, now: start.advanced(by: .seconds(3))))
    }

    @Test("The backstop forces a read once the last one is old enough")
    func backstopReads() {
        let gate = gate(readAt: start)
        let backstop = OwnerLivenessGate<Int>.backstop
        #expect(!gate.isReadDue(ownersAlive: true, signature: 1, now: start.advanced(by: backstop - .seconds(1))))
        #expect(gate.isReadDue(ownersAlive: true, signature: 1, now: start.advanced(by: backstop)))
    }

    @Test("A read is trusted from when it was noted, under the list it saw")
    func noteReadReplacesTheLastRead() {
        var gate = gate(readAt: start)
        let later = start.advanced(by: .seconds(40))
        gate.noteRead(signature: 2, at: later)
        #expect(!gate.isReadDue(ownersAlive: true, signature: 2, now: later.advanced(by: .seconds(3))))
        #expect(gate.isReadDue(ownersAlive: true, signature: 1, now: later.advanced(by: .seconds(3))))
    }
}
