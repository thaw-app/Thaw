//
//  SlowResponderLedgerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("The slow responder ledger backs off owners that miss AX deadlines")
struct SlowResponderLedgerTests {
    private let start = ContinuousClock.now

    @Test("An owner with no record is probed")
    func unknownOwnerIsProbed() {
        let ledger = SlowResponderLedger()
        #expect(ledger.decision(for: 42, now: start) == .probe)
        #expect(ledger.strikes(for: 42) == 0)
    }

    @Test("A timed-out probe in flight suppresses another until it returns")
    func inFlightSuppresses() {
        var ledger = SlowResponderLedger()
        let cooldown = ledger.timedOut(42, now: start)

        #expect(cooldown == SlowResponderLedger.baseCooldown)
        #expect(ledger.strikes(for: 42) == 1)
        #expect(ledger.decision(for: 42, now: start + .seconds(10)) == .skipInFlight)

        ledger.lateAnswerArrived(42)
        #expect(ledger.decision(for: 42, now: start + .seconds(1)) == .skipCoolingDown)
        #expect(ledger.decision(for: 42, now: start + .seconds(6)) == .probeIfResponsive)
    }

    @Test("A probe that never returns stops suppressing after the in-flight limit")
    func inFlightLimitExpires() {
        var ledger = SlowResponderLedger()
        ledger.timedOut(7, now: start)
        let later = start + SlowResponderLedger.inFlightLimit + .seconds(1)
        #expect(ledger.decision(for: 7, now: later) == .probeIfResponsive)
    }

    @Test("Consecutive strikes double the cooldown up to the maximum")
    func cooldownDoublesAndCaps() {
        var ledger = SlowResponderLedger()
        let cooldowns = (0 ..< 6).map { _ in ledger.stillUnresponsive(9, now: start) }
        #expect(cooldowns == [.seconds(5), .seconds(10), .seconds(20), .seconds(30), .seconds(30), .seconds(30)])
        #expect(ledger.strikes(for: 9) == 6)
        #expect(ledger.decision(for: 9, now: start + .seconds(29)) == .skipCoolingDown)
    }

    @Test("A timely answer clears the owner")
    func answerClears() {
        var ledger = SlowResponderLedger()
        ledger.timedOut(3, now: start)
        ledger.answered(3)
        #expect(ledger.decision(for: 3, now: start) == .probe)
        #expect(ledger.strikes(for: 3) == 0)
    }

    @Test("Records for owners no longer running are dropped")
    func retainRunningOwners() {
        var ledger = SlowResponderLedger()
        ledger.stillUnresponsive(1, now: start)
        ledger.stillUnresponsive(2, now: start)

        ledger.retain(runningOwners: [2])

        #expect(ledger.strikes(for: 1) == 0)
        #expect(ledger.strikes(for: 2) == 1)
    }
}
