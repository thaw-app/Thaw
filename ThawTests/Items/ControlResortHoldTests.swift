//
//  ControlResortHoldTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Control re-sorts wait while the hiding restriction is applied or the bar is still reflowing after it.
@MainActor
@Suite("Control re-sort hold")
struct ControlResortHoldTests {
    private let start = ContinuousClock.now
    private let window = Duration.seconds(10)

    private func signal(changedAt: Duration?, applying: Bool = false) -> ControlResortHold.Signal {
        ControlResortHold.Signal(
            restrictionChangedAt: changedAt.map { start + $0 },
            isRestrictionBeingApplied: applying,
            settleWindow: window
        )
    }

    private func hold(changedAt: Duration?, applying: Bool = false, now: Duration) -> ControlResortHold? {
        ControlResortHold.current(signal(changedAt: changedAt, applying: applying), now: start + now)
    }

    @Test("With no hiding change, a re-sort may run")
    func noRestrictionChange() {
        #expect(hold(changedAt: nil, now: .seconds(5)) == nil)
    }

    @Test("Inside the settle window a re-sort waits for what is left of it")
    func insideSettleWindow() throws {
        let found = try #require(hold(changedAt: .seconds(1), now: .seconds(4)))
        #expect(found == .settling(remaining: .seconds(7)))
        #expect(found.retryAfter == .seconds(7) + ControlResortHold.margin)
        #expect(found.reason.contains("settling"))
    }

    @Test("Once the window has passed a re-sort may run")
    func afterSettleWindow() {
        #expect(hold(changedAt: .seconds(1), now: .seconds(11)) == nil)
        #expect(hold(changedAt: .seconds(1), now: .seconds(30)) == nil)
    }

    @Test("While the restriction is being applied a re-sort waits, even long after the last change")
    func whileApplying() throws {
        let found = try #require(hold(changedAt: nil, applying: true, now: .seconds(60)))
        #expect(found == .restrictionBeingApplied)
        #expect(found.retryAfter == .seconds(1))
        #expect(found.reason.contains("being applied"))
        #expect(hold(changedAt: .seconds(1), applying: true, now: .seconds(2)) == .restrictionBeingApplied)
    }

    @Test("A hold stretches the debounce to outlast it, and never shortens it")
    func debounceOutlastsTheHold() {
        let debounce = Duration.milliseconds(800)
        #expect(ControlResortHold.debounce(debounce, hold: nil) == debounce)
        #expect(ControlResortHold.debounce(debounce, hold: .settling(remaining: .seconds(3))) == .seconds(3) + ControlResortHold.margin)
        #expect(ControlResortHold.debounce(.seconds(5), hold: .restrictionBeingApplied) == .seconds(5))
    }

    @Test("The logged checks follow the hold")
    func loggedChecks() {
        let held = signal(changedAt: .seconds(1))
        #expect(!ControlResortHold.allowsResort(for: "test", held, now: start + .seconds(2)))
        #expect(ControlResortHold.allowsResort(for: "test", held, now: start + .seconds(12)))
        #expect(ControlResortHold.debounce(.milliseconds(800), for: "test", held, now: start + .seconds(2)) == .seconds(9) + ControlResortHold.margin)
        #expect(ControlResortHold.debounce(.milliseconds(800), for: "test", nil, now: start + .seconds(2)) == .milliseconds(800))
    }

    @Test("A fresh item manager holds nothing")
    func freshManagerSignal() {
        let signal = ControlResortHold.Signal(of: MenuBarItemManager())
        #expect(signal.restrictionChangedAt == nil)
        #expect(!signal.isRestrictionBeingApplied)
        #expect(signal.settleWindow == MenuBarItemManager.restrictionChangeLayoutSettleWindow)
    }
}
