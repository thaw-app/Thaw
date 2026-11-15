//
//  AccessRefusalLedgerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
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
