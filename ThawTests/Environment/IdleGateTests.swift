//
//  IdleGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Testing
@testable import Thaw

@Suite("Idle gate state")
struct IdleGateStateTests {
    @Test("Idle work runs only once the displays are awake and the session is active", arguments: [
        ([], true),
        ([.displaysSlept], false),
        ([.displaysSlept, .displaysWoke], true),
        ([.sessionResigned], false),
        ([.sessionResigned, .sessionBecameActive], true),
        ([.sessionResigned, .displaysSlept, .displaysWoke], false),
        ([.sessionResigned, .displaysSlept, .displaysWoke, .sessionBecameActive], true),
        ([.displaysSlept, .sessionResigned, .sessionBecameActive], false),
        ([.displaysSlept, .sessionResigned, .sessionBecameActive, .displaysWoke], true),
        ([.displaysWoke, .sessionBecameActive], true),
        ([.displaysSlept, .displaysSlept, .displaysWoke, .sessionResigned], false),
    ] as [([IdleGateState.Signal], Bool)])
    func mayRunIdleWork(after signals: [IdleGateState.Signal], expected: Bool) {
        #expect(signals.reduce(IdleGateState()) { $0.applying($1) }.mayRunIdleWork == expected)
    }
}

@Suite("Idle gate")
@MainActor
struct IdleGateTests {
    @Test("Subscribers hear each flip once, from the workspace notifications")
    func notifiesFlips() {
        let center = NotificationCenter()
        let gate = IdleGate(center: center)
        var heard: [Bool] = []
        let token = gate.subscribe { heard.append($0) }
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(heard == [false, true])
        token.cancel()
        gate.note(.displaysSlept)
        #expect(heard == [false, true], "A released token hears nothing")
    }

    @Test("A gated timer exists only while the gate is open and resumes with one call")
    func gatedTimer() async {
        let (resumes, resumed) = AsyncStream.makeStream(of: Void.self)
        let timer = IdleGatedTimer(interval: 60, tolerance: 1, mode: .default, onResume: { resumed.yield() }, tick: { /* Never fires in a test this short. */ })
        timer.apply(mayRun: true, resuming: false)
        #expect(timer.isArmed)
        timer.apply(mayRun: false, resuming: false)
        #expect(!timer.isArmed)
        timer.apply(mayRun: true, resuming: true)
        #expect(timer.isArmed)
        var iterator = resumes.makeAsyncIterator()
        await iterator.next()
        timer.apply(mayRun: false, resuming: false)
        #expect(!timer.isArmed)
    }

    @Test("A repeating token resumes its owner when the gate opens again")
    func repeatingResumes() async {
        let gate = IdleGate(center: NotificationCenter())
        let (resumes, resumed) = AsyncStream.makeStream(of: Void.self)
        let token = gate.repeating(every: 60, tolerance: 1, onResume: { resumed.yield() }, tick: { /* Never fires in a test this short. */ })
        gate.note(.displaysSlept)
        gate.note(.displaysWoke)
        var iterator = resumes.makeAsyncIterator()
        await iterator.next()
        token.cancel()
    }
}
