//
//  MenuBarAgentLayoutWaitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// A clock that only moves when the wait sleeps, and a bar that answers from a script.
@MainActor
private final class FakeAgentBar {
    struct Cancelled: Error {}

    let start = ContinuousClock.now
    private(set) var elapsed: Duration = .zero
    private(set) var sleeps: [Duration] = []
    private(set) var reads = 0
    private(set) var deadlineAsks = 0
    private let script: [[MenuBarItem]?]
    private let throwOnSleep: Int?

    /// - Parameters:
    ///   - script: What each read returns, in order; the last entry repeats.
    ///   - throwOnSleep: The 1-based sleep that throws instead of returning.
    init(script: [[MenuBarItem]?], throwOnSleep: Int? = nil) {
        self.script = script
        self.throwOnSleep = throwOnSleep
    }

    var now: ContinuousClock.Instant {
        start + elapsed
    }

    func read() -> [MenuBarItem]? {
        defer { reads += 1 }
        return script[min(reads, script.count - 1)]
    }

    func sleep(_ duration: Duration) throws {
        sleeps.append(duration)
        if sleeps.count == throwOnSleep {
            throw Cancelled()
        }
        elapsed += duration
    }

    func fallbackDeadline(after limit: Duration) -> ContinuousClock.Instant {
        deadlineAsks += 1
        return start + limit
    }

    func wait(
        deadline: ContinuousClock.Instant? = nil,
        fallback: Duration = .seconds(10),
        interval: Duration = .milliseconds(250),
        earlyBailProbe: Duration? = nil,
        isSatisfied: ([MenuBarItem]) -> Bool = { _ in false }
    ) async -> MenuBarAgentLayoutWait.Result {
        await MenuBarAgentLayoutWait.run(
            deadline: deadline,
            fallbackDeadline: { fallbackDeadline(after: fallback) },
            interval: interval,
            earlyBailProbe: earlyBailProbe,
            now: { now },
            sleep: { try sleep($0) },
            enumerate: { read() },
            isSatisfied: isSatisfied
        )
    }
}

@MainActor
@Suite("MenuBarAgent layout wait")
struct MenuBarAgentLayoutWaitTests {
    private static let a = item("A", x: 10)
    private static let b = item("B", x: 40)
    private static let aShifted = item("A", x: 90)

    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private static func result(
        items: [MenuBarItem] = [],
        barMoved: Bool = false,
        cancelled: Bool = false,
        observationUnavailable: Bool = false
    ) -> MenuBarAgentLayoutWait.Result {
        MenuBarAgentLayoutWait.Result(
            items: items, barMoved: barMoved, cancelled: cancelled, observationUnavailable: observationUnavailable
        )
    }

    // MARK: Poll loop

    @Test("An unreadable bar on the first read ends the wait without sleeping or asking for a deadline")
    func unreadableFirstRead() async {
        let bar = FakeAgentBar(script: [nil])
        let outcome = await bar.wait()
        #expect(outcome.observationUnavailable)
        #expect(outcome.items.isEmpty)
        #expect(!outcome.barMoved)
        #expect(!outcome.cancelled)
        #expect(bar.sleeps.isEmpty)
        #expect(bar.deadlineAsks == 0)
    }

    @Test("An unreadable first read inside a cancelled task is reported as cancelled")
    func unreadableFirstReadWhileCancelled() async {
        let bar = FakeAgentBar(script: [nil])
        let task = Task { @MainActor in
            while !Task.isCancelled {
                await Task.yield()
            }
            return await bar.wait()
        }
        task.cancel()
        let outcome = await task.value
        #expect(outcome.observationUnavailable)
        #expect(outcome.cancelled)
    }

    @Test("A bar that already shows the write returns after one read, with no sleep and no motion")
    func satisfiedOnFirstRead() async {
        let bar = FakeAgentBar(script: [[Self.a, Self.b]])
        let outcome = await bar.wait(isSatisfied: { $0.count == 2 })
        #expect(outcome.items == [Self.a, Self.b])
        #expect(!outcome.barMoved)
        #expect(!outcome.cancelled)
        #expect(!outcome.observationUnavailable)
        #expect(bar.reads == 1)
        #expect(bar.sleeps.isEmpty)
    }

    @Test("The fallback deadline is asked once, after the first read, only when none was given")
    func fallbackDeadlineIsAskedOnlyWhenNeeded() async {
        let fallingBack = FakeAgentBar(script: [[Self.a]])
        _ = await fallingBack.wait(isSatisfied: { _ in true })
        #expect(fallingBack.deadlineAsks == 1)

        let explicit = FakeAgentBar(script: [[Self.a]])
        _ = await explicit.wait(deadline: explicit.start + .seconds(1), isSatisfied: { _ in true })
        #expect(explicit.deadlineAsks == 0)
    }

    @Test("A wait polls at the interval and returns the read that satisfied it, flagging motion")
    func satisfiedAfterAPoll() async {
        // The bar is unchanged on the first poll, then A shifts and the check passes.
        let bar = FakeAgentBar(script: [[Self.a, Self.b], [Self.a, Self.b], [Self.aShifted, Self.b]])
        let outcome = await bar.wait(
            interval: .milliseconds(100),
            isSatisfied: { $0.first?.bounds.minX == 90 }
        )
        #expect(outcome.items == [Self.aShifted, Self.b])
        #expect(outcome.barMoved)
        #expect(!outcome.cancelled)
        #expect(bar.sleeps == [.milliseconds(100), .milliseconds(100)])
        #expect(bar.reads == 3)
    }

    @Test("A frozen bar is polled until the deadline and then returned unsatisfied")
    func deadlineEndsAFrozenWait() async {
        let bar = FakeAgentBar(script: [[Self.a, Self.b]])
        let outcome = await bar.wait(deadline: bar.start + .seconds(1))
        #expect(outcome.items == [Self.a, Self.b])
        #expect(!outcome.barMoved)
        #expect(!outcome.cancelled)
        #expect(!outcome.observationUnavailable)
        // 250 ms steps from 0 to the 1 s deadline.
        #expect(bar.sleeps.count == 4)
    }

    @Test("A deadline already in the past polls nothing")
    func pastDeadlinePollsNothing() async {
        let bar = FakeAgentBar(script: [[Self.a]])
        let outcome = await bar.wait(deadline: bar.start - .seconds(1))
        #expect(outcome.items == [Self.a])
        #expect(bar.sleeps.isEmpty)
        #expect(bar.reads == 1)
    }

    @Test("A frozen bar ends the wait at the early-bail probe, not the deadline")
    func earlyBailEndsAFrozenWait() async {
        let bar = FakeAgentBar(script: [[Self.a, Self.b]])
        let outcome = await bar.wait(
            deadline: bar.start + .seconds(5),
            earlyBailProbe: .milliseconds(700)
        )
        #expect(!outcome.barMoved)
        // Polls land at 250, 500 and 750 ms; the third is the first at or past 700.
        #expect(bar.sleeps.count == 3)
        #expect(bar.now == bar.start + .milliseconds(750))
    }

    @Test("Once the bar has moved, the early-bail probe no longer ends the wait")
    func earlyBailLatchesOffOnMotion() async {
        // A shifts on the first poll and then stays put.
        let bar = FakeAgentBar(script: [[Self.a, Self.b], [Self.aShifted, Self.b]])
        let outcome = await bar.wait(
            deadline: bar.start + .seconds(2),
            earlyBailProbe: .milliseconds(300)
        )
        #expect(outcome.barMoved)
        // The wait runs its course: 250 ms steps up to the 2 s deadline.
        #expect(bar.sleeps.count == 8)
    }

    @Test("Without a probe a frozen bar is not cut short")
    func noProbeNoEarlyBail() async {
        let bar = FakeAgentBar(script: [[Self.a]])
        _ = await bar.wait(deadline: bar.start + .seconds(2), earlyBailProbe: nil)
        #expect(bar.sleeps.count == 8)
    }

    @Test("A satisfied poll ends the wait before the probe is consulted")
    func satisfiedBeatsEarlyBail() async {
        let bar = FakeAgentBar(script: [[Self.a], [Self.a]])
        let outcome = await bar.wait(
            deadline: bar.start + .seconds(5),
            earlyBailProbe: .milliseconds(100),
            isSatisfied: { _ in bar.reads >= 2 }
        )
        #expect(bar.sleeps.count == 1)
        #expect(!outcome.barMoved)
    }

    @Test("A sleep that throws ends the wait as cancelled, keeping the last read and any motion")
    func cancellationDuringASleep() async {
        let bar = FakeAgentBar(script: [[Self.a, Self.b], [Self.aShifted, Self.b]], throwOnSleep: 2)
        let outcome = await bar.wait(deadline: bar.start + .seconds(5))
        #expect(outcome.cancelled)
        #expect(outcome.barMoved)
        #expect(!outcome.observationUnavailable)
        #expect(outcome.items == [Self.aShifted, Self.b])
        // No enumeration after the sleep that threw.
        #expect(bar.reads == 2)
    }

    @Test("A bar that becomes unreadable mid-wait reports unavailable and keeps the motion it saw")
    func unreadableMidWait() async {
        let bar = FakeAgentBar(script: [[Self.a, Self.b], [Self.aShifted, Self.b], nil])
        let outcome = await bar.wait(deadline: bar.start + .seconds(5))
        #expect(outcome.observationUnavailable)
        #expect(outcome.barMoved)
        #expect(outcome.items.isEmpty)
        #expect(!outcome.cancelled)
    }

    @Test("An item blinking in and out is not motion")
    func blinkingRowsAreNotMotion() async {
        let bar = FakeAgentBar(script: [[Self.a, Self.b], [Self.a], [Self.a, Self.b]])
        let outcome = await bar.wait(deadline: bar.start + .milliseconds(750))
        #expect(!outcome.barMoved)
    }

    // MARK: Move verdict

    @Test("An unreadable bar outranks everything, and the check is not asked")
    func unreadableBarIsFirst() {
        var asked = false
        let verdict = MenuBarAgentLayoutWait.moveVerdict(
            of: Self.result(barMoved: true, observationUnavailable: true),
            isSatisfied: {
                asked = true
                return true
            }
        )
        #expect(verdict == .observationUnavailable)
        #expect(!asked)
    }

    @Test("A bar that shows the move is verified, whether or not it shifted")
    func satisfiedMoveIsVerified() {
        #expect(MenuBarAgentLayoutWait.moveVerdict(of: Self.result(barMoved: false), isSatisfied: { true }) == .verified)
        #expect(MenuBarAgentLayoutWait.moveVerdict(of: Self.result(barMoved: true), isSatisfied: { true }) == .verified)
    }

    @Test("A frozen bar that does not show the move means the agent dropped the write")
    func frozenUnsatisfiedBarIsIgnored() {
        #expect(MenuBarAgentLayoutWait.moveVerdict(of: Self.result(barMoved: false), isSatisfied: { false }) == .agentIgnored)
    }

    @Test("A bar that shifted without showing the move is left for a refreshed write")
    func shiftedUnsatisfiedBarIsUnsatisfied() {
        #expect(MenuBarAgentLayoutWait.moveVerdict(of: Self.result(barMoved: true), isSatisfied: { false }) == .unsatisfied)
    }

    // MARK: Resort verdict

    @Test("A satisfied order wins over every other reading")
    func satisfiedResortWins() {
        for moved in [false, true] {
            for cancelled in [false, true] {
                for nudged in [false, true] {
                    let verdict = MenuBarAgentLayoutWait.resortVerdict(
                        of: Self.result(barMoved: moved, cancelled: cancelled, observationUnavailable: true),
                        satisfied: true,
                        nudgeRan: nudged
                    )
                    #expect(verdict == .satisfied)
                }
            }
        }
    }

    @Test("A frozen bar after a nudge is a write the agent ignored")
    func frozenAfterNudgeIsIgnored() {
        let verdict = MenuBarAgentLayoutWait.resortVerdict(of: Self.result(), satisfied: false, nudgeRan: true)
        #expect(verdict == .agentIgnored)
    }

    @Test("A frozen bar with no nudge is unverified, not evidence against the agent")
    func frozenWithoutNudgeIsUnverified() {
        let verdict = MenuBarAgentLayoutWait.resortVerdict(of: Self.result(), satisfied: false, nudgeRan: false)
        #expect(verdict == .unverified)
    }

    @Test("A bar that moved proves nothing against the agent")
    func movedBarIsInconclusive() {
        for nudged in [false, true] {
            let verdict = MenuBarAgentLayoutWait.resortVerdict(
                of: Self.result(barMoved: true), satisfied: false, nudgeRan: nudged
            )
            #expect(verdict == .inconclusive)
        }
    }

    @Test("A cancelled wait proves nothing against the agent")
    func cancelledWaitIsInconclusive() {
        for nudged in [false, true] {
            let verdict = MenuBarAgentLayoutWait.resortVerdict(
                of: Self.result(cancelled: true), satisfied: false, nudgeRan: nudged
            )
            #expect(verdict == .inconclusive)
        }
    }

    // MARK: Retry deadline

    @Test("The retry keeps the phase deadline while it leaves at least three polls")
    func retryKeepsALongPhaseDeadline() {
        let now = ContinuousClock.now
        let phase = now + .seconds(5)
        #expect(MenuBarAgentLayoutWait.retryDeadline(phaseDeadline: phase, now: now, pollInterval: .milliseconds(250)) == phase)
    }

    @Test("A spent phase budget still leaves the retry three polls")
    func retryNeverGetsFewerThanThreePolls() {
        let now = ContinuousClock.now
        let spent = now - .seconds(1)
        #expect(
            MenuBarAgentLayoutWait.retryDeadline(phaseDeadline: spent, now: now, pollInterval: .milliseconds(250))
                == now + .milliseconds(750)
        )
        // A budget with less than three polls left is extended to three.
        let nearlySpent = now + .milliseconds(100)
        #expect(
            MenuBarAgentLayoutWait.retryDeadline(phaseDeadline: nearlySpent, now: now, pollInterval: .milliseconds(250))
                == now + .milliseconds(750)
        )
    }
}
