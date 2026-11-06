//
//  LeadingEdgePollIntervalTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Leading edge poll interval")
struct LeadingEdgePollIntervalTests {
    private let now = ContinuousClock.now

    @Test("An idle bar is polled at the idle interval")
    func idleWithoutAWindow() {
        let interval = MenuBarLeadingEdgeWatcher.pollInterval(now: now, fastUntil: nil)
        #expect(interval == MenuBarLeadingEdgeWatcher.pollInterval)
    }

    @Test("Inside the window after a change the bar is polled fast")
    func fastInsideTheWindow() {
        let interval = MenuBarLeadingEdgeWatcher.pollInterval(now: now, fastUntil: now + .seconds(1))
        #expect(interval == MenuBarLeadingEdgeWatcher.fastPollInterval)
    }

    @Test("Once the window has passed polling returns to idle")
    func idleAfterTheWindow() {
        let interval = MenuBarLeadingEdgeWatcher.pollInterval(now: now, fastUntil: now - .milliseconds(1))
        #expect(interval == MenuBarLeadingEdgeWatcher.pollInterval)
    }

    @MainActor
    @Test("Expecting a change opens the fast window, and expecting another extends it")
    func expectChangeOpensAndExtendsTheWindow() throws {
        let watcher = MenuBarLeadingEdgeWatcher()
        #expect(watcher.fastPollUntil == nil, "A watcher nobody warned polls at the idle interval")

        let before = ContinuousClock.now
        watcher.expectChange()
        let after = ContinuousClock.now
        let first = try #require(watcher.fastPollUntil)
        #expect(first >= before + MenuBarLeadingEdgeWatcher.fastPollWindow)
        #expect(first <= after + MenuBarLeadingEdgeWatcher.fastPollWindow)
        #expect(MenuBarLeadingEdgeWatcher.pollInterval(now: after, fastUntil: first) == MenuBarLeadingEdgeWatcher.fastPollInterval)

        watcher.expectChange()
        let second = try #require(watcher.fastPollUntil)
        #expect(second >= first, "A later sign of change must never shorten the window")
        #expect(watcher.leadingEdge == nil, "Expecting a change is not itself a reading")
    }
}
