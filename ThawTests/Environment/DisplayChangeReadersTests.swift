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
@Suite("Display change readers", .serialized, .timeLimit(.minutes(1)))
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

    /// Lets a main-queue hop in a reader's pipeline run.
    private func drainMainQueue() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("The overlay rebuilds at each settle, and once after a burst of postings")
    func overlayRebuildSignal() async throws {
        var rebuilds = 0
        let invalidations = PassthroughSubject<Void, Never>()
        let settlements = PassthroughSubject<EnvironmentChange, Never>()
        let signal = MenuBarAppearanceManager.overlayRebuildSignal(invalidations: invalidations, settlements: settlements)
            .sink { rebuilds += 1 }
        defer { signal.cancel() }

        settlements.send(.none)
        #expect(rebuilds == 1, "A settle rebuilds at once, even when nothing moved")

        for _ in 0 ..< 3 {
            invalidations.send()
        }
        #expect(rebuilds == 1, "Postings wait out their burst")
        try await Task.sleep(for: .milliseconds(300))
        #expect(rebuilds == 2, "A burst of postings rebuilds once, before the settle")
    }

    @Test("The Thaw Bar drops its colour strip at the settle, not at the posting")
    func thawBarColorWaitsForSettle() async throws {
        environment.start()
        defer {
            gate.open()
            environment.stop()
        }
        let appState = AppState()
        let colorManager = ThawBarColorManager()
        colorManager.performSetup(with: ThawBarPanel(), appState: appState, displaySettlements: environment.settlements)
        try await drainMainQueue()
        let before = colorManager.windowImageGeneration

        postScreenChange()
        try await drainMainQueue()
        #expect(colorManager.windowImageGeneration == before, "The posting alone leaves the strip")

        gate.open()
        await environment.waitUntilSettled()
        try await drainMainQueue()
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
