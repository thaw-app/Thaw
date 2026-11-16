//
//  AccessRefusalRestartTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Restarting when apps refuse Accessibility reads")
@MainActor
struct AccessRefusalRestartTests {
    /// What the check was told, and how often it asked the refusing apps.
    @MainActor
    private final class Facts {
        var refusers: Set<pid_t> = [1, 2, 3]
        var formerHosts = 4
        var processTrusted = true
        var helperTrusted = true
        var startedByRestart = false
        var refuserReads = 0
        var restarts = 0

        func probe() -> AccessRefusalRestart.Probe {
            AccessRefusalRestart.Probe(
                refusers: {
                    self.refuserReads += 1
                    return self.refusers
                },
                formerHosts: { self.formerHosts },
                processTrusted: { self.processTrusted },
                helperTrusted: { self.helperTrusted },
                startedByRestart: { self.startedByRestart }
            )
        }
    }

    private let facts = Facts()

    private func check() async -> Bool {
        await AccessRefusalRestart.restartIfRefused(probe: facts.probe()) { facts.restarts += 1 }
    }

    @Test("It restarts once when the permission is granted, the helper can read and enough apps refuse")
    func restarts() async {
        #expect(await check())
        #expect(facts.restarts == 1)
    }

    @Test("It leaves Thaw running when one app refuses, or a few among many that answer")
    func tooFewRefusers() async {
        facts.refusers = [1]
        #expect(await !check())
        facts.refusers = [1, 2, 3]
        facts.formerHosts = 14
        #expect(await !check())
        #expect(facts.restarts == 0)
    }

    @Test("It does not ask the apps again when the permission is missing or this copy came from a restart")
    func cheapFactsFirst() async {
        facts.processTrusted = false
        #expect(await !check())
        facts.processTrusted = true
        facts.helperTrusted = false
        #expect(await !check())
        facts.helperTrusted = true
        facts.startedByRestart = true
        #expect(await !check())
        #expect(facts.refuserReads == 0)
        #expect(facts.restarts == 0)
    }

    @Test("The live facts read this process, where no app refuses and no helper has answered")
    func liveFacts() async {
        let probe = AccessRefusalRestart.Probe.live
        #expect(await probe.refusers().isEmpty)
        #expect(probe.formerHosts() >= 0)
        #expect(!probe.helperTrusted())
        #expect(!probe.startedByRestart())
        _ = probe.processTrusted()
        var restarts = 0
        #expect(await !AccessRefusalRestart.restartIfRefused { restarts += 1 })
        #expect(restarts == 0)
    }
}

@Suite("Apps the walk found refusing", .serialized)
struct AccessRefusersTests {
    private let start = ContinuousClock.now
    /// Process IDs no real process has, so the shared ledger holds nothing else of theirs.
    private let first: pid_t = 9_100_001
    private let second: pid_t = 9_100_002
    private let third: pid_t = 9_100_003

    @Test("Apps that refused for a while and still refuse are reported; one that answers now is not")
    func stillRefusing() async {
        for pid in [first, second, third] {
            MenuBarItemAXProvider.noteAccessAnswer(.apiDisabled, from: pid, now: start)
        }
        let later = start + AccessRefusalRecovery.minimumDuration
        let third = third
        let refusers = await MenuBarItemAXProvider.persistentAccessRefusers(
            running: [first, second, third], now: later, read: { $0 == third ? .noValue : .apiDisabled }
        )
        #expect(refusers == [first, second])
        let again = await MenuBarItemAXProvider.persistentAccessRefusers(
            running: [first, second, third], now: later, read: { _ in .success }
        )
        #expect(again.isEmpty)
    }

    @Test("Apps that only just refused, quit, or are too few are not asked")
    func notAsked() async {
        MenuBarItemAXProvider.noteAccessAnswer(.apiDisabled, from: first, now: start)
        MenuBarItemAXProvider.noteAccessAnswer(.apiDisabled, from: second, now: start)
        let read: @Sendable (pid_t) -> AXError = { _ in
            Issue.record("No app should be asked")
            return .apiDisabled
        }
        let early = start + AccessRefusalRecovery.minimumDuration - .seconds(1)
        #expect(await MenuBarItemAXProvider.persistentAccessRefusers(running: [first, second], now: early, read: read).isEmpty)
        let later = start + AccessRefusalRecovery.minimumDuration
        #expect(await MenuBarItemAXProvider.persistentAccessRefusers(running: [first], now: later, read: read).isEmpty)
        #expect(await MenuBarItemAXProvider.persistentAccessRefusers(running: [first, second], now: later, read: read).isEmpty)
    }

    @Test("Reading an app's extras bar the raw way records how it answered")
    @MainActor
    func rawReadIsRecorded() async {
        // The test process has no extras bar, so the read never succeeds; a refusal is recorded as one.
        let result = MenuBarItemAXProvider.recordedExtrasBarRead(pid: getpid())
        #expect(result != .success)
        let later = ContinuousClock.now + AccessRefusalRecovery.minimumDuration
        let refusers = await MenuBarItemAXProvider.persistentAccessRefusers(running: [getpid()], now: later, read: { _ in result })
        #expect(refusers.isEmpty, "One app is never enough")
        #expect(!MenuBarAXSubprocess.helperIsTrusted)
    }

    @Test("The helper counts as trusted only after a trusted answer, and not after an untrusted one")
    func helperTrust() {
        var policy = UntrustedHelperPolicy()
        #expect(!policy.lastAnswerWasTrusted)
        _ = policy.noteTrusted()
        #expect(policy.lastAnswerWasTrusted)
        _ = policy.noteUntrusted(now: start)
        #expect(!policy.lastAnswerWasTrusted)
    }
}
