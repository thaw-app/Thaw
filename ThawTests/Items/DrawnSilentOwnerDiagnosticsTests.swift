//
//  DrawnSilentOwnerDiagnosticsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import ApplicationServices
import CoreGraphics
import Testing
@testable import Thaw
import ThawAXCore

@MainActor
struct DrawnSilentOwnerDiagnosticsTests {
    private let timeout = Duration.milliseconds(250)

    private func classify(_ result: AXError, ms: Int64, children: Int? = nil) -> EmptyExtrasBarOutcome {
        EmptyExtrasBarOutcome.classify(result: result, duration: .milliseconds(ms), childCount: children, timeout: timeout)
    }

    @Test
    func `a cannot-complete answer after about the timeout is a slow responder`() {
        #expect(classify(.cannotComplete, ms: 251) == .slowResponder)
        #expect(classify(.cannotComplete, ms: 210) == .slowResponder)
    }

    @Test
    func `an immediate cannot-complete answer means no accessibility server`() {
        #expect(classify(.cannotComplete, ms: 1) == .noAccessibilityServer)
    }

    @Test
    func `no value or an unsupported attribute means no extras bar`() {
        #expect(classify(.noValue, ms: 1) == .noExtrasBar)
        #expect(classify(.attributeUnsupported, ms: 1) == .noExtrasBar)
    }

    @Test
    func `a successful read with no children is an empty extras bar`() {
        #expect(classify(.success, ms: 2, children: 0) == .emptyExtrasBar)
        #expect(classify(.success, ms: 2) == .emptyExtrasBar)
    }

    @Test
    func `a successful read with children means the walk raced the app`() {
        #expect(classify(.success, ms: 2, children: 1) == .publishedItems(1))
    }

    @Test
    func `other errors are failures`() {
        #expect(classify(.apiDisabled, ms: 1) == .failed)
    }

    @Test
    func `only drawn owners that answered empty are silent`() {
        let drawn = [
            MenuBarAgentWindow.Entry(ownerPID: 10, frame: CGRect(x: 100, y: 0, width: 30, height: 24)),
            MenuBarAgentWindow.Entry(ownerPID: 11, frame: CGRect(x: 140, y: 0, width: 30, height: 24)),
            MenuBarAgentWindow.Entry(ownerPID: 10, frame: CGRect(x: 180, y: 0, width: 20, height: 24)),
        ]
        let silent = DrawnSilentOwnerDiagnostics.silentEntries(drawn: drawn, answeredEmpty: [10, 12])
        #expect(Set(silent.keys) == [10])
        #expect(silent[10]?.map(\.frame.width) == [30, 20])
    }

    @Test
    func `an owner is probed again only after the interval and never twice at once`() {
        let now = ContinuousClock.now
        #expect(DrawnSilentOwnerDiagnostics.admits(lastProbe: nil, inFlight: false, now: now))
        #expect(!DrawnSilentOwnerDiagnostics.admits(lastProbe: nil, inFlight: true, now: now))
        #expect(!DrawnSilentOwnerDiagnostics.admits(lastProbe: now - .seconds(10), inFlight: false, now: now))
        #expect(DrawnSilentOwnerDiagnostics.admits(lastProbe: now - .seconds(60), inFlight: false, now: now))
    }

    @Test
    func `the log line names the owner, its entries and both reads`() {
        let owner = DrawnSilentOwnerDiagnostics.Owner(pid: 42, bundleID: "com.example.app", activationPolicy: 1, entryWidths: [30])
        let read = EmptyExtrasBarProbe(rawResult: AXError.noValue.rawValue, duration: .microseconds(800), outcome: .noExtrasBar)
        let message = DrawnSilentOwnerDiagnostics.message(for: owner, first: read, retry: read)
        #expect(message == """
        menuBarItems: com.example.app (pid 42, policy 1) is drawn (1 entry, w=30) but gave no items: \
        extrasBar=absent rawRead=-25212 (no extras bar) in 1 ms; retry(1.0 s)=-25212 (no extras bar) in 1 ms
        """)
    }

    @Test
    func `a read of a process that does not exist finds no extras bar`() {
        let probe = EmptyExtrasBarProbe.run(pid: 999_999)
        #expect(!probe.hasBar)
        #expect(probe.outcome != .emptyExtrasBar)
    }

    @Test(.timeLimit(.minutes(1)))
    func `probes a silent drawn owner once per interval and never this app`() async throws {
        let sleeps = RecordedSleeps()
        let diagnostics = DrawnSilentOwnerDiagnostics(retryDelay: .milliseconds(10)) { try sleeps.sleep(for: $0) }
        let drawn = [
            MenuBarAgentWindow.Entry(ownerPID: 999_999, frame: CGRect(x: 100, y: 0, width: 30, height: 24)),
            MenuBarAgentWindow.Entry(ownerPID: getpid(), frame: CGRect(x: 140, y: 0, width: 30, height: 24)),
        ]
        let apps = [999_999: NSRunningApplication.current, getpid(): NSRunningApplication.current]
        let probed = diagnostics.note(drawn: drawn, answeredEmpty: [999_999, getpid()], apps: apps)
        #expect(probed.map(\.pid) == [999_999])
        #expect(diagnostics.note(drawn: drawn, answeredEmpty: [999_999, getpid()], apps: apps).isEmpty)
        await sleeps.waitForSleeps(1)
        #expect(sleeps.durations == [.milliseconds(10)])
        // The retry read follows on the probe's own task, which says nothing when it ends, so its
        // end is waited for under the time limit rather than a deadline of its own.
        while !diagnostics.probesInFlight.isEmpty {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(diagnostics.probesInFlight.isEmpty)
        #expect(diagnostics.note(drawn: drawn, answeredEmpty: [999_999], apps: apps).isEmpty)
    }

    @Test
    func `a walk uses the drawn reading only when it is recent`() {
        let ledger = DrawnBarLedger()
        let now = ContinuousClock.now
        let entry = MenuBarAgentWindow.Entry(ownerPID: 10, frame: CGRect(x: 0, y: 0, width: 30, height: 24))
        #expect(ledger.reading(since: now - .seconds(1)) == nil)
        #expect(ledger.read(using: { [entry] }, now: now) == [entry])
        #expect(ledger.reading(since: now - .seconds(1))?.entries == [entry])
        #expect(ledger.reading(since: now + .seconds(1)) == nil)
        _ = ledger.read(using: { nil }, now: now)
        #expect(ledger.reading(since: now).map { $0.entries == nil } == true)
    }
}
