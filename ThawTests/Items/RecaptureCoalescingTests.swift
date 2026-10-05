//
//  RecaptureCoalescingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Recapture coalescing")
struct RecaptureCoalescingTests {
    private typealias Demand = RecaptureDemand

    // MARK: Merge policy

    @Test("Merged demand captures every requested section once, in bar order")
    func mergedSectionsAccumulate() {
        let merged = Demand(sections: [.visible, .hidden], ignoreRecentMove: false)
            .merged(into: Demand(sections: [.alwaysHidden, .hidden], ignoreRecentMove: false))
        #expect(merged == Demand(sections: [.visible, .hidden, .alwaysHidden], ignoreRecentMove: false))
    }

    @Test("A forced refresh stays forced whichever side of the merge it is on", arguments: [
        (true, false), (false, true), (true, true),
    ])
    func forcedRefreshSurvivesMerging(pendingForced: Bool, incomingForced: Bool) {
        let merged = Demand(sections: [.visible], ignoreRecentMove: incomingForced)
            .merged(into: Demand(sections: [.hidden], ignoreRecentMove: pendingForced))
        #expect(merged.ignoreRecentMove)
        #expect(merged.sections == [.visible, .hidden])
    }

    @Test("A lone request is passed through untouched")
    func loneRequestIsUnchanged() {
        let demand = Demand(sections: [.hidden, .visible, .hidden], ignoreRecentMove: false)
        #expect(demand.merged(into: nil) == demand)
    }

    // MARK: Placement

    @Test("With no pass running a request starts one")
    func idleStarts() {
        let demand = Demand(sections: [.visible], ignoreRecentMove: false)
        #expect(demand.placement(capturableNow: [.visible], running: nil) == .start)
    }

    @Test("A pass that has not started absorbs any request, forced or not", arguments: [false, true])
    func unstartedPassAbsorbs(forced: Bool) {
        let demand = Demand(sections: [.hidden], ignoreRecentMove: forced)
        let placement = demand.placement(
            capturableNow: [.hidden],
            running: .init(capturing: nil, hasWaiters: true)
        )
        #expect(placement == .mergeIntoRunning)
    }

    @Test("A started pass is shared only by requests it already covers")
    func startedPassSharesCoveredRequests() {
        let running = Demand.RunningPass(capturing: [.visible, .hidden], hasWaiters: true)
        let covered = Demand(sections: [.visible], ignoreRecentMove: false)
        #expect(covered.placement(capturableNow: [.visible], running: running) == .joinRunning)

        let otherSection = Demand(sections: [.visible, .alwaysHidden], ignoreRecentMove: false)
        #expect(otherSection.placement(capturableNow: [.visible, .alwaysHidden], running: running) == .followUp)
    }

    @Test("Coverage is judged on what is capturable, not on what was named")
    func coverageUsesCapturableSections() {
        // The running pass was asked for Hidden before it was revealed, so it skipped it.
        let running = Demand.RunningPass(capturing: [.visible], hasWaiters: true)
        let demand = Demand(sections: [.visible, .hidden], ignoreRecentMove: false)
        #expect(demand.placement(capturableNow: [.visible, .hidden], running: running) == .followUp)
        #expect(demand.placement(capturableNow: [.visible], running: running) == .joinRunning)
    }

    @Test("A forced refresh never shares a pass that already started", arguments: [false, true])
    func forcedRefreshGetsItsOwnPass(runningIsForcedToo _: Bool) {
        let running = Demand.RunningPass(capturing: [.visible, .hidden, .alwaysHidden], hasWaiters: true)
        let forced = Demand(sections: [.visible], ignoreRecentMove: true)
        #expect(forced.placement(capturableNow: [.visible], running: running) == .followUp)
    }

    @Test("A pass nobody awaits is cancelled, so it serves no new request", arguments: [
        Set<MenuBarSection.Name>?.none, [.visible],
    ])
    func abandonedPassServesNobody(capturing: Set<MenuBarSection.Name>?) {
        let demand = Demand(sections: [.visible], ignoreRecentMove: false)
        let placement = demand.placement(
            capturableNow: [.visible],
            running: .init(capturing: capturing, hasWaiters: false)
        )
        #expect(placement == .followUp)
    }

    // MARK: In-flight bookkeeping

    @Test("A covered request arriving mid-pass shares that pass")
    func coveredRequestSharesThePass() async {
        let coalescer = RecaptureCoalescer()
        let probe = PassProbe()
        let all = Demand(sections: [.visible, .hidden], ignoreRecentMove: false)
        let first = Task { await probe.run(all, on: coalescer) }
        await probe.waitForPasses(1)
        let second = Task { await probe.run(Demand(sections: [.visible], ignoreRecentMove: false), on: coalescer) }
        await settle()
        probe.finishPass(returning: true)

        #expect(await first.value)
        #expect(await second.value)
        #expect(probe.demands == [all])
    }

    @Test("Requests the running pass cannot serve collapse into one forced follow-up")
    func uncoveredRequestsShareOneFollowUp() async {
        let coalescer = RecaptureCoalescer()
        let probe = PassProbe()
        let live = Demand(sections: [.visible], ignoreRecentMove: false)
        let first = Task { await probe.run(live, on: coalescer) }
        await probe.waitForPasses(1)

        let reorder = Task { await probe.run(Demand(sections: [.visible], ignoreRecentMove: true), on: coalescer) }
        let prewarm = Task { await probe.run(Demand(sections: [.hidden], ignoreRecentMove: false), on: coalescer) }
        await settle()
        #expect(probe.demands == [live], "The follow-up must not overlap the running pass")

        probe.finishPass(returning: false)
        await probe.waitForPasses(2)
        probe.finishPass(returning: true)

        #expect(await first.value == false)
        #expect(await reorder.value)
        #expect(await prewarm.value)
        #expect(probe.demands == [live, Demand(sections: [.visible, .hidden], ignoreRecentMove: true)])
    }

    @Test("A forced refresh still runs when the pass ahead of it is cancelled")
    func forcedRefreshOutlivesACancelledPass() async {
        let coalescer = RecaptureCoalescer()
        let probe = PassProbe()
        let first = Task { await probe.run(Demand(sections: [.visible], ignoreRecentMove: false), on: coalescer) }
        await probe.waitForPasses(1)
        let forced = Demand(sections: [.visible], ignoreRecentMove: true)
        let reorder = Task { await probe.run(forced, on: coalescer) }
        await settle()

        first.cancel()
        await settle()
        #expect(probe.cancelledPasses == 1)
        probe.finishPass(returning: false)
        await probe.waitForPasses(2)
        probe.finishPass(returning: true)

        #expect(await reorder.value)
        #expect(probe.demands.last == forced)
        #expect(probe.cancelledPasses == 1, "Cancelling one caller must not cancel another caller's pass")
    }

    @Test("A shared pass survives one caller's cancellation and stops with the last")
    func cancellationFollowsTheLastWaiter() async {
        let coalescer = RecaptureCoalescer()
        let probe = PassProbe()
        let demand = Demand(sections: [.visible], ignoreRecentMove: false)
        let first = Task { await probe.run(demand, on: coalescer) }
        await probe.waitForPasses(1)
        let second = Task { await probe.run(demand, on: coalescer) }
        await settle()

        first.cancel()
        await settle()
        #expect(probe.cancelledPasses == 0)
        second.cancel()
        await settle()
        #expect(probe.cancelledPasses == 1)

        probe.finishPass(returning: false)
        _ = await first.value
        _ = await second.value
        #expect(probe.demands == [demand])
    }

    @Test("Requests that arrive before the pass starts are folded into that one pass")
    func requestsBeforeTheStartShareOnePass() async {
        let coalescer = RecaptureCoalescer()
        let probe = PassProbe()
        let first = Task { await probe.run(Demand(sections: [.hidden], ignoreRecentMove: false), on: coalescer) }
        let second = Task { await probe.run(Demand(sections: [.visible], ignoreRecentMove: true), on: coalescer) }
        await probe.waitForPasses(1)
        await settle()
        probe.finishPass(returning: true)

        #expect(await first.value)
        #expect(await second.value)
        #expect(probe.demands == [Demand(sections: [.visible, .hidden], ignoreRecentMove: true)])
    }

    @Test("A follow-up whose only caller gave up never runs, and frees its slot")
    func abandonedFollowUpNeverRuns() async {
        let coalescer = RecaptureCoalescer()
        let probe = PassProbe()
        let live = Demand(sections: [.visible], ignoreRecentMove: false)
        let first = Task { await probe.run(live, on: coalescer) }
        await probe.waitForPasses(1)
        let forced = Task { await probe.run(Demand(sections: [.visible], ignoreRecentMove: true), on: coalescer) }
        await settle()

        forced.cancel()
        await settle()
        probe.finishPass(returning: true)
        #expect(await first.value)
        #expect(await forced.value == false)
        await settle()
        #expect(probe.demands == [live], "A pass nobody waits for must not capture")
        #expect(probe.cancelledPasses == 0, "Giving up on the follow-up must not cancel the running pass")

        let next = Demand(sections: [.hidden], ignoreRecentMove: false)
        let later = Task { await probe.run(next, on: coalescer) }
        await probe.waitForPasses(2)
        probe.finishPass(returning: true)
        #expect(await later.value)
        #expect(probe.demands == [live, next])
    }

    @Test("A caller cancelled before it asks starts nothing")
    func cancelledCallerStartsNothing() async {
        let coalescer = RecaptureCoalescer()
        let probe = PassProbe()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await probe.run(Demand(sections: [.visible], ignoreRecentMove: false), on: coalescer)
        }
        #expect(await task.value == false)
        #expect(probe.demands.isEmpty)
    }

    /// Lets every task already scheduled on the main actor run.
    private func settle() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }
}

/// A pass body the test finishes by hand, recording what each pass was asked for.
@MainActor
private final class PassProbe {
    private(set) var demands = [RecaptureDemand]()
    private(set) var cancelledPasses = 0
    private var inFlight = [CheckedContinuation<Bool, Never>]()

    func run(_ demand: RecaptureDemand, on coalescer: RecaptureCoalescer) async -> Bool {
        await coalescer.run(demand, capturable: { $0 }, pass: { [self] demand in
            demands.append(demand)
            return await withTaskCancellationHandler {
                await withCheckedContinuation { inFlight.append($0) }
            } onCancel: {
                Task { @MainActor in self.cancelledPasses += 1 }
            }
        })
    }

    func finishPass(returning result: Bool) {
        inFlight.removeFirst().resume(returning: result)
    }

    func waitForPasses(_ count: Int) async {
        for _ in 0 ..< 10000 where demands.count < count || inFlight.count < 1 {
            await Task.yield()
        }
    }
}
