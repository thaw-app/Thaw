//
//  MenuBarWalkGuardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

@Suite("Apps that refuse Accessibility reads")
struct AccessRefusalLedgerTests {
    private let start = ContinuousClock.now

    @Test("An app counts once it has refused for long enough without answering")
    func refusersNeedTime() {
        var ledger = AccessRefusalLedger()
        ledger.refused(10, at: start)
        ledger.refused(11, at: start + .seconds(8))
        #expect(ledger.refusers(lasting: .seconds(10), now: start + .seconds(9)).isEmpty)
        #expect(ledger.refusers(lasting: .seconds(10), now: start + .seconds(12)) == [10])
        #expect(ledger.refusers(lasting: .seconds(10), now: start + .seconds(20)) == [10, 11])
    }

    @Test("A later refusal keeps the time of the first")
    func firstRefusalIsKept() {
        var ledger = AccessRefusalLedger()
        ledger.refused(10, at: start)
        ledger.refused(10, at: start + .seconds(9))
        #expect(ledger.refusers(lasting: .seconds(10), now: start + .seconds(10)) == [10])
    }

    @Test("An app that answers stops counting, and counts from its next refusal")
    func answerClears() {
        var ledger = AccessRefusalLedger()
        ledger.refused(10, at: start)
        ledger.answered(10)
        #expect(ledger.refusers(lasting: .zero, now: start + .seconds(30)).isEmpty)
        ledger.refused(10, at: start + .seconds(30))
        #expect(ledger.refusers(lasting: .seconds(10), now: start + .seconds(35)).isEmpty)
        #expect(ledger.refusers(lasting: .seconds(10), now: start + .seconds(40)) == [10])
    }

    @Test("An app that quit is forgotten")
    func quitAppsAreForgotten() {
        var ledger = AccessRefusalLedger()
        ledger.refused(10, at: start)
        ledger.refused(11, at: start)
        ledger.retain(running: [11, 12])
        #expect(ledger.refusers(lasting: .zero, now: start) == [11])
    }
}

@Suite("Restarting when apps refuse Accessibility reads")
struct AccessRefusalRecoveryTests {
    private func facts(
        refusers: Int = 3, formerHosts: Int = 4, processTrusted: Bool = true, helperTrusted: Bool = true, startedByRestart: Bool = false
    ) -> AccessRefusalRecovery.Facts {
        AccessRefusalRecovery.Facts(
            refusers: refusers,
            formerHosts: formerHosts,
            processTrusted: processTrusted,
            helperTrusted: helperTrusted,
            startedByRestart: startedByRestart
        )
    }

    @Test("It restarts when the permission is granted, a newer process can read and enough apps refuse")
    func restarts() {
        #expect(AccessRefusalRecovery.shouldRestart(facts()))
        #expect(AccessRefusalRecovery.shouldRestart(facts(refusers: AccessRefusalRecovery.minimumOwners)))
    }

    @Test("One refusing app is not enough, even when it is the only app that had items")
    func oneAppIsNotEnough() {
        #expect(!AccessRefusalRecovery.shouldRestart(facts(refusers: AccessRefusalRecovery.minimumOwners - 1, formerHosts: 1)))
        #expect(!AccessRefusalRecovery.shouldRestart(facts(refusers: 0)))
    }

    @Test("A few refusing apps among many that answer are their own business; half of them is not")
    func refusersMustBeHalf() {
        #expect(!AccessRefusalRecovery.shouldRestart(facts(refusers: 2, formerHosts: 14)))
        #expect(!AccessRefusalRecovery.shouldRestart(facts(refusers: 6, formerHosts: 13)))
        #expect(AccessRefusalRecovery.shouldRestart(facts(refusers: 7, formerHosts: 14)))
        #expect(AccessRefusalRecovery.shouldRestart(facts(refusers: 11, formerHosts: 13)))
    }

    @Test("It does not restart when the permission is missing, since a new process would be refused too")
    func missingPermission() {
        #expect(!AccessRefusalRecovery.shouldRestart(facts(processTrusted: false)))
        #expect(!AccessRefusalRecovery.shouldRestart(facts(helperTrusted: false)))
    }

    @Test("A copy started by a restart does not restart again")
    func restartsOnce() {
        #expect(!AccessRefusalRecovery.shouldRestart(facts(startedByRestart: true)))
    }
}

/// Counts jobs running at once.
private actor InFlight {
    private(set) var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
    }
}

@Suite("Bounded walk")
struct BoundedWalkTests {
    @Test("No more than the limit run at once, and every job's answer is collected")
    func limitsConcurrencyAndCollectsAll() async {
        let inFlight = InFlight()
        var collected: [Int] = []
        await BoundedWalk.run(Array(0 ..< 20), limit: 4) { item in
            .run {
                await inFlight.enter()
                try? await Task.sleep(for: .milliseconds(10))
                await inFlight.leave()
                return item
            }
        } collect: { collected.append($0) }

        #expect(collected.sorted() == Array(0 ..< 20))
        #expect(await inFlight.peak <= 4)
        #expect(await inFlight.peak > 1)
    }

    @Test("A skipped item runs nothing, and stop starts nothing more but collects what is running")
    func skipAndStop() async {
        var started: [Int] = []
        var collected: [Int] = []
        await BoundedWalk.run(Array(0 ..< 10), limit: 3) { item in
            if item == 1 { return .skip }
            if item == 5 { return .stop }
            started.append(item)
            return .run { item }
        } collect: { collected.append($0) }

        #expect(started == [0, 2, 3, 4])
        #expect(collected.sorted() == [0, 2, 3, 4])
    }

    @Test("An item is only considered once a slot is free, so its checks see the time it would start")
    func startWaitsForAFreeSlot() async {
        let inFlight = InFlight()
        var busyAtStart: [Int] = []
        await BoundedWalk.run(Array(0 ..< 8), limit: 2) { item in
            await busyAtStart.append(inFlight.current)
            return .run {
                await inFlight.enter()
                try? await Task.sleep(for: .milliseconds(5))
                await inFlight.leave()
                return item
            }
        } collect: { _ in }

        #expect(busyAtStart.allSatisfy { $0 < 2 })
    }
}

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
