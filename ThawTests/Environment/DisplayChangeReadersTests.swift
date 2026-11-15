//
//  DisplayChangeReadersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Testing
@testable import Thaw

/// The postings go to a private center, since the default one would reach the app hosting the tests.
@MainActor
@Suite("Display change readers", .serialized, .scratchDefaults)
struct DisplayChangeReadersTests {
    private let center = NotificationCenter()
    private let gate = SettleGate()
    private let environment: DisplayEnvironment

    init() {
        let arrangement = DisplayArrangement(frames: [1: CGRect(x: 0, y: 0, width: 1512, height: 982)], mainDisplayID: 1)
        environment = DisplayEnvironment(
            center: center,
            baseline: arrangement,
            read: { arrangement },
            sleep: { [gate] _ in
                await gate.pass()
                try Task.checkCancellation()
            }
        )
    }

    private func postScreenChange() {
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Lets a main-queue hop in a reader's pipeline run. The main queue runs its blocks in the order
    /// they were queued, so the block queued here runs after any hop queued before it.
    private func drainMainQueue() async {
        await withCheckedContinuation { drained in
            DispatchQueue.main.async { drained.resume() }
        }
    }

    @Test("The overlay rebuilds at each settle, and once after a burst of postings")
    func overlayRebuildSignal() {
        var rebuilds = 0
        let invalidations = PassthroughSubject<Void, Never>()
        let settlements = PassthroughSubject<EnvironmentChange, Never>()
        let scheduler = ManualScheduler()
        let signal = MenuBarAppearanceManager.overlayRebuildSignal(
            invalidations: invalidations,
            settlements: settlements,
            scheduler: scheduler
        )
        .sink { rebuilds += 1 }
        defer { signal.cancel() }

        settlements.send(.none)
        #expect(rebuilds == 1, "A settle rebuilds at once, even when nothing moved")

        for _ in 0 ..< 3 {
            invalidations.send()
        }
        #expect(rebuilds == 1, "Postings wait out their burst")
        scheduler.advance(by: .milliseconds(100))
        #expect(rebuilds == 2, "A burst of postings rebuilds once, before the settle")
    }

    @Test("The Thaw Bar drops its colour strip at the settle, not at the posting")
    func thawBarColorWaitsForSettle() async {
        environment.start()
        defer {
            gate.open()
            environment.stop()
        }
        let appState = AppState()
        let colorManager = ThawBarColorManager()
        colorManager.performSetup(with: ThawBarPanel(), appState: appState, displaySettlements: environment.settlements)
        await drainMainQueue()
        let before = colorManager.windowImageGeneration

        postScreenChange()
        await drainMainQueue()
        #expect(colorManager.windowImageGeneration == before, "The posting alone leaves the strip")

        gate.open()
        await environment.waitUntilSettled()
        await drainMainQueue()
        #expect(colorManager.windowImageGeneration == before + 1)
    }

    /// The panel takes only the invalidations, so a settle cannot reach it.
    @Test("The search panel closes at the posting")
    func searchPanelClosesAtPosting() {
        environment.start()
        defer {
            gate.open()
            environment.stop()
        }
        let appState = AppState()
        let panel = MenuBarSearchPanel()
        panel.performSetup(with: appState, displayInvalidations: environment.invalidations)
        appState.navigationState.isSearchPresented = true

        postScreenChange()
        #expect(!appState.navigationState.isSearchPresented)
    }

    @Test("The Thaw Bar hides at the posting once it has been up a second")
    func thawBarHidesAtPosting() async throws {
        let screen = try #require(NSScreen.main)
        environment.start()
        let appState = AppState()
        let panel = ThawBarPanel()
        let settlements = PassthroughSubject<EnvironmentChange, Never>()
        let originalPolicy = NSApp.activationPolicy()
        defer {
            panel.close()
            NSApp.setActivationPolicy(originalPolicy)
            gate.open()
            environment.stop()
        }
        NSApp.setActivationPolicy(.accessory)
        panel.performSetup(with: appState, displayInvalidations: environment.invalidations, displaySettlements: settlements)
        panel.dismissesOnOutsideClick = false
        panel.show(section: .hidden, on: screen)
        try await Task.sleep(for: .milliseconds(1100))
        #expect(panel.isVisible)

        settlements.send(.displayAdded)
        #expect(panel.isVisible, "A settle on its own leaves the bar up")

        postScreenChange()
        #expect(!panel.isVisible)
    }
}

/// Holds the settle's waits until a test lets them through, so a test can look between the posting and the settle.
@MainActor
private final class SettleGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let released = waiters
        waiters.removeAll()
        for waiter in released {
            waiter.resume()
        }
    }
}

/// A Combine scheduler whose clock only the test advances, so a debounce fires exactly when told.
/// The test drives it from the main actor only.
private nonisolated final class ManualScheduler: Scheduler {
    typealias SchedulerTimeType = DispatchQueue.SchedulerTimeType
    typealias SchedulerOptions = Never

    private nonisolated struct Action {
        let date: SchedulerTimeType
        let run: () -> Void
    }

    private(set) var now = SchedulerTimeType(DispatchTime(uptimeNanoseconds: 1))
    private var pending: [Action] = []

    var minimumTolerance: SchedulerTimeType.Stride {
        .zero
    }

    func schedule(options _: Never?, _ action: @escaping () -> Void) {
        action()
    }

    func schedule(after date: SchedulerTimeType, tolerance _: SchedulerTimeType.Stride, options _: Never?, _ action: @escaping () -> Void) {
        pending.append(Action(date: date, run: action))
    }

    func schedule(
        after date: SchedulerTimeType,
        interval: SchedulerTimeType.Stride,
        tolerance _: SchedulerTimeType.Stride,
        options _: Never?,
        _ action: @escaping () -> Void
    ) -> Cancellable {
        let cancellable = Repeat()
        repeatAction(cancellable, at: date, every: interval, action)
        return cancellable
    }

    /// Runs every action due by then, earliest first, with the clock at each one's time.
    func advance(by stride: SchedulerTimeType.Stride) {
        let target = now.advanced(by: stride)
        while let index = pending.indices.filter({ pending[$0].date <= target }).min(by: { pending[$0].date < pending[$1].date }) {
            let action = pending.remove(at: index)
            now = action.date
            action.run()
        }
        now = target
    }

    private func repeatAction(_ cancellable: Repeat, at date: SchedulerTimeType, every interval: SchedulerTimeType.Stride, _ action: @escaping () -> Void) {
        pending.append(Action(date: date) { [weak self] in
            guard !cancellable.isCancelled else { return }
            action()
            self?.repeatAction(cancellable, at: date.advanced(by: interval), every: interval, action)
        })
    }

    private nonisolated final class Repeat: Cancellable {
        private(set) var isCancelled = false

        func cancel() {
            isCancelled = true
        }
    }
}
