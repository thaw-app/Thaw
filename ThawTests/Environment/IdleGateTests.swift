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
    private func state(after signals: [IdleGateState.Signal]) -> IdleGateState {
        signals.reduce(IdleGateState()) { $0.applying($1) }
    }

    @Test("Idle work runs until a signal says nobody is looking")
    func startsOpen() {
        #expect(IdleGateState().mayRunIdleWork)
    }

    @Test("Display sleep pauses and wake resumes")
    func displaySleep() {
        #expect(!state(after: [.displaysSlept]).mayRunIdleWork)
        #expect(state(after: [.displaysSlept, .displaysWoke]).mayRunIdleWork)
    }

    @Test("An inactive session pauses and a return resumes")
    func session() {
        #expect(!state(after: [.sessionResigned]).mayRunIdleWork)
        #expect(state(after: [.sessionResigned, .sessionBecameActive]).mayRunIdleWork)
    }

    @Test("Waking before the session returns stays paused until it does")
    func wakeBeforeActive() {
        let asleepAndAway = state(after: [.sessionResigned, .displaysSlept])
        #expect(!asleepAndAway.applying(.displaysWoke).mayRunIdleWork)
        #expect(asleepAndAway.applying(.displaysWoke).applying(.sessionBecameActive).mayRunIdleWork)
    }

    @Test("The session returning before the displays wake stays paused until they do")
    func activeBeforeWake() {
        let asleepAndAway = state(after: [.displaysSlept, .sessionResigned])
        #expect(!asleepAndAway.applying(.sessionBecameActive).mayRunIdleWork)
        #expect(asleepAndAway.applying(.sessionBecameActive).applying(.displaysWoke).mayRunIdleWork)
    }

    @Test("A repeated or unmatched signal changes nothing on its own")
    func repeatedSignals() {
        #expect(state(after: [.displaysWoke, .sessionBecameActive]).mayRunIdleWork)
        #expect(!state(after: [.displaysSlept, .displaysSlept, .displaysWoke, .sessionResigned]).mayRunIdleWork)
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
        let gate = IdleGate(center: NotificationCenter())
        let (resumes, resumed) = AsyncStream.makeStream(of: Void.self)
        let timer = IdleGatedTimer(interval: 60, tolerance: 1, mode: .default, onResume: { resumed.yield() }, tick: { /* Never fires in a test this short. */ })
        timer.apply(mayRun: gate.mayRunIdleWork, resuming: false)
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
