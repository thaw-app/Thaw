//
//  ExtrasBarAbsenceLedgerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import os.lock
import Testing
@testable import Thaw

@Suite("Walks leave out apps that keep answering with no extras menu bar")
struct ExtrasBarAbsenceLedgerTests {
    private typealias Ledger = ExtrasBarAbsenceLedger
    private let start = ContinuousClock.now
    private let bundleID = "com.example.agent"

    /// A ledger that has seen the same absence twice, far enough apart to count.
    private func confirmed(_ absence: Ledger.Absence, pid: pid_t = 42) -> Ledger {
        var ledger = Ledger()
        ledger.noteAnswer(absence, pid: pid, bundleID: bundleID, now: start)
        ledger.noteAnswer(absence, pid: pid, bundleID: bundleID, now: start + Ledger.confirmationDelay)
        return ledger
    }

    @Test("No value and unsupported mean the app has no extras bar")
    func plainAnswersAreNoExtrasBar() {
        #expect(Ledger.absence(for: .noValue, elapsed: .milliseconds(15)) == .noExtrasBar)
        #expect(Ledger.absence(for: .attributeUnsupported, elapsed: .milliseconds(10)) == .noExtrasBar)
    }

    @Test("A read that fails at once means no Accessibility server, and one that fails late is a timeout")
    func cannotCompleteDependsOnTime() {
        #expect(Ledger.absence(for: .cannotComplete, elapsed: .zero) == .noAXServer)
        #expect(Ledger.absence(for: .cannotComplete, elapsed: Ledger.immediateFailureLimit) == nil)
        #expect(Ledger.absence(for: .cannotComplete, elapsed: .milliseconds(250)) == nil)
    }

    @Test("A refusal, a failure or a bar is not an absence")
    func otherAnswersAreNotAbsences() {
        for result in [AXError.success, .apiDisabled, .failure, .invalidUIElement, .notImplemented] {
            #expect(Ledger.absence(for: result, elapsed: .zero) == nil)
        }
    }

    @Test("An app is asked again until its answer holds for the confirmation delay")
    func oneAnswerIsNotEnough() {
        var ledger = Ledger()
        #expect(!ledger.skips(42, bundleID: bundleID, now: start))

        ledger.noteAnswer(.noAXServer, pid: 42, bundleID: bundleID, now: start)
        #expect(!ledger.skips(42, bundleID: bundleID, now: start))

        ledger.noteAnswer(.noAXServer, pid: 42, bundleID: bundleID, now: start + .seconds(5))
        #expect(!ledger.skips(42, bundleID: bundleID, now: start + .seconds(5)))

        let later = start + Ledger.confirmationDelay
        ledger.noteAnswer(.noAXServer, pid: 42, bundleID: bundleID, now: later)
        #expect(ledger.skips(42, bundleID: bundleID, now: later))
    }

    @Test("A confirmed app is asked again after its recheck interval, and a new absence renews it")
    func confirmedAnswerExpires() {
        var ledger = confirmed(.noExtrasBar)
        let confirmedAt = start + Ledger.confirmationDelay
        let interval = Ledger.Absence.noExtrasBar.recheckInterval
        #expect(ledger.skips(42, bundleID: bundleID, now: confirmedAt + interval - .seconds(1)))
        #expect(!ledger.skips(42, bundleID: bundleID, now: confirmedAt + interval))

        ledger.noteAnswer(.noExtrasBar, pid: 42, bundleID: bundleID, now: confirmedAt + interval)
        #expect(ledger.skips(42, bundleID: bundleID, now: confirmedAt + interval + .seconds(1)))
    }

    @Test("An app with an Accessibility server is checked more often than one without")
    func recheckIntervals() {
        #expect(Ledger.Absence.noExtrasBar.recheckInterval < Ledger.Absence.noAXServer.recheckInterval)
        let ledger = confirmed(.noAXServer)
        let probe = start + Ledger.confirmationDelay + Ledger.Absence.noExtrasBar.recheckInterval
        #expect(ledger.skips(42, bundleID: bundleID, now: probe))
    }

    @Test("Any other answer forgets the app at once")
    func otherAnswerForgets() {
        var ledger = confirmed(.noExtrasBar)
        ledger.noteAnswer(nil, pid: 42, bundleID: bundleID, now: start + .seconds(40))
        #expect(!ledger.skips(42, bundleID: bundleID, now: start + .seconds(41)))
    }

    @Test("A different answer starts the confirmation again")
    func changedAbsenceRestarts() {
        var ledger = confirmed(.noAXServer)
        let changedAt = start + .seconds(40)
        ledger.noteAnswer(.noExtrasBar, pid: 42, bundleID: bundleID, now: changedAt)
        #expect(!ledger.skips(42, bundleID: bundleID, now: changedAt))
    }

    @Test("A new process that reuses the pid is asked")
    func reusedPIDIsAsked() {
        var ledger = confirmed(.noAXServer)
        #expect(!ledger.skips(42, bundleID: "com.example.other", now: start + .seconds(31)))

        ledger.noteAnswer(.noAXServer, pid: 42, bundleID: "com.example.other", now: start + .seconds(31))
        #expect(!ledger.skips(42, bundleID: "com.example.other", now: start + .seconds(32)))
        #expect(!ledger.skips(42, bundleID: bundleID, now: start + .seconds(32)))
    }

    @Test("An app that quit is dropped")
    func quitAppIsDropped() {
        var ledger = confirmed(.noAXServer, pid: 7)
        ledger.retain(running: [8])
        #expect(!ledger.skips(7, bundleID: bundleID, now: start + .seconds(31)))
    }

    @Test("The warning about Thaw's own extras bar fires when the bar goes and when it returns, not on every read")
    func ownBarChangesOnlyOnTransitions() {
        let state = OSAllocatedUnfairLock(initialState: false)
        #expect(!MenuBarItemAXProvider.ownExtrasBarChanged(isMissing: false, in: state))
        #expect(MenuBarItemAXProvider.ownExtrasBarChanged(isMissing: true, in: state))
        #expect(!MenuBarItemAXProvider.ownExtrasBarChanged(isMissing: true, in: state))
        #expect(MenuBarItemAXProvider.ownExtrasBarChanged(isMissing: false, in: state))
        #expect(!MenuBarItemAXProvider.ownExtrasBarChanged(isMissing: false, in: state))
    }
}
