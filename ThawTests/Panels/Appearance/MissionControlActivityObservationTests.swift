//
//  MissionControlActivityObservationTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Testing
@testable import Thaw

/// Observers and a never-shown overlay use committed activity without changing the live menu bar.
@MainActor
@Suite("Mission Control activity observation", .serialized, .scratchDefaults, .timeLimit(.minutes(1)))
struct MissionControlActivityObservationTests {
    /// A queue barrier drains activity notifications without depending on fixed sleeps.
    private func drainNotifications() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Entering hides the overlay without stopping the poll that must detect exit.
    @Test("The overlay hides on entry, keeps polling, and restores on exit")
    func overlayFollowsActivity() async throws {
        let screen = try #require(NSScreen.screens.first)
        let probe = MissionControlShieldProbe(owningScreen: screen)
        let appState = AppState()
        let panel = MenuBarOverlayPanel(appState: appState, owningScreen: screen, missionControlProbe: probe)
        defer { panel.close() }
        let shouldRun = try #require(probe.shouldRun)
        // Keep the timer from overwriting injected activity.
        probe.shouldRun = { false }
        await drainNotifications()
        #expect(!panel.isVisible)
        let restingAlpha = panel.alphaValue
        #expect(probe.isPolling == (restingAlpha > 0))

        for active in [true, false, true, false] {
            probe.isActive = active
            await drainNotifications()
            #expect(panel.alphaValue == (active ? 0 : restingAlpha))
            #expect(shouldRun() == (active || restingAlpha > 0))
            #expect(probe.isPolling == (active || restingAlpha > 0), "an invisible active probe must keep polling to detect exit")
        }
    }

    /// The overlay rereads activity to decide both its alpha and whether to keep polling.
    @Test("Observers read the new activity on entry and exit, including repeated transitions")
    func observesCommittedActivity() async throws {
        let probe = try MissionControlShieldProbe(owningScreen: #require(NSScreen.screens.first))
        let (updates, continuation) = AsyncStream.makeStream(of: Bool.self)
        let observation = probe.activityChanges.sink { _ in continuation.yield(probe.isActive) }
        defer {
            observation.cancel()
            continuation.finish()
        }
        var iterator = updates.makeAsyncIterator()
        #expect(await iterator.next() == false)

        for active in [true, false, true, false] {
            probe.isActive = active
            #expect(await iterator.next() == active)
        }
    }

    /// Teardown must suppress the scheduled initial notification as well as later changes.
    @Test("Cancellation prevents queued and subsequent activity callbacks")
    func cancellationStopsObservation() async throws {
        let probe = try MissionControlShieldProbe(owningScreen: #require(NSScreen.screens.first))
        var callbacks = 0
        let cancelled = probe.activityChanges.sink { _ in callbacks += 1 }
        cancelled.cancel()

        let (updates, continuation) = AsyncStream.makeStream(of: Bool.self)
        let barrier = probe.activityChanges.sink { _ in continuation.yield(probe.isActive) }
        defer {
            barrier.cancel()
            continuation.finish()
        }
        var iterator = updates.makeAsyncIterator()
        #expect(await iterator.next() == false)
        #expect(callbacks == 0)
        probe.isActive = true
        #expect(await iterator.next() == true)
        #expect(callbacks == 0)
    }
}
