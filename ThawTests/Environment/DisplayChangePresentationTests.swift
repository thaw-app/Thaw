//
//  DisplayChangePresentationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Testing
@testable import Thaw

@Suite("Always-show display change hold", .scratchDefaults)
struct AlwaysShowDisplayChangeHoldTests {
    @Test("With no display change in flight a sync runs at once")
    func idleSyncsAtOnce() {
        var hold = AlwaysShowDisplayChangeHold()
        let syncs = [hold.requestSync(), hold.requestSync()]
        #expect(syncs == [true, true])
        #expect(!hold.hasDeferredSync)
    }

    @Test("A posting holds until the run's presentation step, which syncs once", arguments: [
        EnvironmentChange.displayAdded, .displayRemoved, .rearranged, .resolutionOnly,
    ])
    func changedSettleHoldsUntilRunEnds(change: EnvironmentChange) {
        var hold = AlwaysShowDisplayChangeHold()
        hold.invalidate()
        let syncs = [hold.requestSync(), hold.settle(change), hold.requestSync()]
        #expect(syncs == [false, false, false])
        #expect(hold.isHolding)
        let stepSyncs = hold.finishRun()
        #expect(stepSyncs)
        #expect(!hold.isHolding)
        #expect(!hold.hasDeferredSync)
    }

    @Test("An unchanged settle starts no run, so it ends the hold and runs only a deferred sync")
    func unchangedSettleReleases() {
        var hold = AlwaysShowDisplayChangeHold()
        hold.invalidate()
        let quietSettle = hold.settle(.none)
        #expect(!quietSettle)
        #expect(!hold.isHolding)

        hold.invalidate()
        let syncs = [hold.requestSync(), hold.settle(.none)]
        #expect(syncs == [false, true])
        #expect(!hold.hasDeferredSync)
    }

    @Test("An unchanged settle during a run keeps holding until that run ends")
    func unchangedSettleDuringRunKeepsHolding() {
        var hold = AlwaysShowDisplayChangeHold()
        hold.invalidate()
        _ = hold.settle(.displayAdded)
        hold.invalidate()
        let syncs = [hold.requestSync(), hold.settle(.none), hold.finishRun()]
        #expect(syncs == [false, false, true])
    }

    @Test("A posting after the settle keeps the step's sync for the next run")
    func postingDuringRunDefersStepSync() {
        var hold = AlwaysShowDisplayChangeHold()
        hold.invalidate()
        _ = hold.settle(.rearranged)
        hold.invalidate()
        let firstStep = hold.finishRun()
        #expect(!firstStep)
        #expect(hold.hasDeferredSync)
        let syncs = [hold.settle(.resolutionOnly), hold.finishRun()]
        #expect(syncs == [false, true])
    }
}

@MainActor
@Suite("Display change presentation step", .scratchDefaults)
struct DisplayChangePresentationTests {
    @MainActor
    final class Counter {
        var value = 0
    }

    @Test("Always-show holds back from an invalidation to the end of the run, then reveals once")
    func controllerHoldsDuringRun() {
        let state = AlwaysShowHiddenItemsTests.ControllerState()
        state.enabledDisplayIDs = [1]
        let controller = state.makeController()
        let invalidations = PassthroughSubject<Void, Never>()
        let settlements = PassthroughSubject<EnvironmentChange, Never>()
        controller.holdDuringDisplayChanges(invalidations: invalidations, settlements: settlements)

        invalidations.send()
        controller.synchronize()
        #expect(state.reveals.isEmpty)
        settlements.send(.displayAdded)
        controller.synchronize()
        #expect(state.reveals.isEmpty)

        controller.finishDisplayChange()
        #expect(state.reveals == [.hidden])
        state.section = nil
        controller.synchronize()
        #expect(state.reveals == [.hidden, .hidden])
    }

    @Test("An unchanged settle runs the sync the hold kept back")
    func unchangedSettleRunsDeferredSync() {
        let state = AlwaysShowHiddenItemsTests.ControllerState()
        state.enabledDisplayIDs = [1]
        let controller = state.makeController()
        let invalidations = PassthroughSubject<Void, Never>()
        let settlements = PassthroughSubject<EnvironmentChange, Never>()
        controller.holdDuringDisplayChanges(invalidations: invalidations, settlements: settlements)

        invalidations.send()
        controller.synchronize()
        #expect(state.reveals.isEmpty)
        settlements.send(.none)
        #expect(state.reveals == [.hidden])
    }

    @Test("The display-change entry evaluates only while the monitor observes")
    func entryEvaluatesWhileObserving() {
        let reads = Counter()
        let monitor = PresentationMonitor(readPresenting: { reads.value += 1; return false })
        monitor.evaluateAfterDisplayChange()
        #expect(reads.value == 0)

        monitor.startObserving()
        let before = reads.value
        monitor.evaluateAfterDisplayChange()
        #expect(reads.value == before + 1)
    }

    @Test("The sharing poll rests while the displays sleep and evaluates again on waking")
    func pollRestsWhileAsleep() async {
        let reads = Counter()
        let gate = IdleGate(center: NotificationCenter())
        let monitor = PresentationMonitor(readPresenting: { reads.value += 1; return false }, idleGate: gate)
        monitor.startObserving()
        #expect(monitor.isPolling)
        gate.note(.displaysSlept)
        #expect(!monitor.isPolling)
        let asleep = reads.value
        monitor.evaluateAfterDisplayChange()
        #expect(reads.value == asleep + 1, "Still observing, so a display change is still evaluated")
        gate.note(.displaysWoke)
        #expect(monitor.isPolling)
        for _ in 0 ..< 200 where reads.value < asleep + 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(reads.value >= asleep + 2, "The resumed poll evaluates at once")
    }

    @Test("Each settled change's step evaluates the presentation and syncs always-show once")
    func stepEvaluatesAndSyncsOncePerChange() {
        let reads = Counter()
        let monitor = PresentationMonitor(readPresenting: { reads.value += 1; return false })
        monitor.startObserving()
        let state = AlwaysShowHiddenItemsTests.ControllerState()
        state.enabledDisplayIDs = [1]
        let menuBarManager = MenuBarManager()
        menuBarManager.alwaysShowHiddenItemsController = state.makeController()
        let manager = MenuBarItemManager()
        let effects = MenuBarDisplayChangeEffects(itemManager: manager, repairs: manager.repairs, imageCache: MenuBarItemImageCache(), displaySettings: DisplaySettingsManager(), profiles: ProfileManager(), presentationMonitor: monitor, menuBarManager: menuBarManager)
        let before = reads.value

        for settled in 1 ... 2 {
            state.section = nil
            effects.applyPresentationPolicy()
            #expect(reads.value == before + settled)
            #expect(state.reveals.count == settled)
        }
    }
}
