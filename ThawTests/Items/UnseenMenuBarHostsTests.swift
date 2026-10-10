//
//  UnseenMenuBarHostsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Unseen menu bar hosts")
struct UnseenMenuBarHostsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let delay = UnseenMenuBarHosts.confirmationDelay

    @Test("A running host from last session is flagged only after the confirmation delay")
    func flagsAfterDelay() {
        var hosts = UnseenMenuBarHosts(expected: ["iordv.Droppy": 0])
        let changedEarly = hosts.update(seen: [], running: ["iordv.Droppy"], now: start)
        #expect(!changedEarly)
        #expect(hosts.flagged.isEmpty)
        let changedLate = hosts.update(seen: [], running: ["iordv.Droppy"], now: start + delay)
        #expect(changedLate)
        #expect(hosts.flagged == ["iordv.Droppy"])
    }

    @Test("A host that is not running is never flagged")
    func ignoresQuitApps() {
        var hosts = UnseenMenuBarHosts(expected: ["iordv.Droppy": 0])
        _ = hosts.update(seen: [], running: [], now: start)
        _ = hosts.update(seen: [], running: [], now: start + delay * 2)
        #expect(hosts.flagged.isEmpty)
    }

    @Test("Seeing the host clears the flag and its strikes")
    func seeingClears() {
        var hosts = UnseenMenuBarHosts(expected: ["iordv.Droppy": 2])
        _ = hosts.update(seen: [], running: ["iordv.Droppy"], now: start)
        _ = hosts.update(seen: [], running: ["iordv.Droppy"], now: start + delay)
        let changed = hosts.update(seen: ["iordv.Droppy"], running: ["iordv.Droppy"], now: start + delay + 1)
        #expect(changed)
        #expect(hosts.flagged.isEmpty)
        #expect(hosts.persisted() == ["iordv.Droppy": 0])
    }

    @Test("A flagged host carries a strike and is dropped after the last one")
    func strikesOut() {
        var hosts = UnseenMenuBarHosts(expected: ["a": 0, "b": UnseenMenuBarHosts.maximumStrikes - 1])
        _ = hosts.update(seen: [], running: ["a", "b"], now: start)
        _ = hosts.update(seen: [], running: ["a", "b"], now: start + delay)
        #expect(hosts.persisted() == ["a": 1])
    }

    @Test("A host that shows nothing on purpose is not flagged, and keeps its place in the baseline")
    func quietHostIsNotFlagged() {
        var hosts = UnseenMenuBarHosts(expected: ["com.example.app": 1])
        _ = hosts.update(seen: [], running: ["com.example.app"], quiet: ["com.example.app"], now: start)
        let changed = hosts.update(
            seen: [], running: ["com.example.app"], quiet: ["com.example.app"], now: start + delay * 2
        )
        #expect(!changed)
        #expect(hosts.flagged.isEmpty)
        #expect(hosts.persisted() == ["com.example.app": 1])
    }

    @Test("A flagged host that turns out to be quiet is dropped from the warning")
    func quietClearsTheFlag() {
        var hosts = UnseenMenuBarHosts(expected: ["com.example.app": 0])
        _ = hosts.update(seen: [], running: ["com.example.app"], now: start)
        _ = hosts.update(seen: [], running: ["com.example.app"], now: start + delay)
        #expect(hosts.flagged == ["com.example.app"])

        let changed = hosts.update(
            seen: [], running: ["com.example.app"], quiet: ["com.example.app"], now: start + delay + 1
        )
        #expect(changed)
        #expect(hosts.flagged.isEmpty)
    }

    @Test("A host that stops being quiet waits out the delay again")
    func noLongerQuietStartsOver() {
        var hosts = UnseenMenuBarHosts(expected: ["com.example.app": 0])
        _ = hosts.update(seen: [], running: ["com.example.app"], quiet: ["com.example.app"], now: start)
        _ = hosts.update(seen: [], running: ["com.example.app"], now: start + delay)
        #expect(hosts.flagged.isEmpty)
        _ = hosts.update(seen: [], running: ["com.example.app"], now: start + delay * 2)
        #expect(hosts.flagged == ["com.example.app"])
    }

    @Test("Hosts seen this session become the next session's baseline")
    func learnsNewHosts() {
        var hosts = UnseenMenuBarHosts(expected: [:])
        _ = hosts.update(seen: ["com.raycast.macos"], running: ["com.raycast.macos"], now: start)
        #expect(hosts.persisted() == ["com.raycast.macos": 0])
    }
}

@Suite("Untrusted helper policy")
struct UntrustedHelperPolicyTests {
    private let start = ContinuousClock.now

    @Test("Each untrusted answer waits longer, then retries rarely")
    func backsOff() {
        var policy = UntrustedHelperPolicy()
        #expect(policy.shouldAsk(now: start))
        var elapsed = Duration.zero
        for backoff in UntrustedHelperPolicy.backoffs {
            let result = policy.noteUntrusted(now: start + elapsed)
            #expect(result.retryAfter == backoff)
            #expect(!result.isGivingUp)
            #expect(!policy.shouldAsk(now: start + elapsed + backoff - .milliseconds(1)))
            elapsed += backoff
            #expect(policy.shouldAsk(now: start + elapsed))
        }
        let last = policy.noteUntrusted(now: start + elapsed)
        #expect(last.retryAfter == UntrustedHelperPolicy.rareRetry)
        #expect(last.isGivingUp)
    }

    @Test("A trusted answer resets the backoff and reports the recovery once")
    func resets() {
        var policy = UntrustedHelperPolicy()
        _ = policy.noteUntrusted(now: start)
        let recovered = policy.noteTrusted()
        let recoveredAgain = policy.noteTrusted()
        #expect(recovered)
        #expect(!recoveredAgain)
        #expect(policy.shouldAsk(now: start))
        let next = policy.noteUntrusted(now: start)
        #expect(next.retryAfter == UntrustedHelperPolicy.backoffs[0])
    }
}
