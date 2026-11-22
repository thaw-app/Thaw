//
//  MissionControlProbeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import CoreGraphics
import Testing
@testable import Thaw

@Suite("Mission Control probe")
struct MissionControlProbeTests {
    private let rest = CGPoint(x: 960, y: 539)

    @Test("macOS 27 takes the probe off screen without moving it, and that counts as displaced")
    func offScreenCounts() {
        #expect(MissionControlShieldProbe.isDisplaced(isOnScreen: false, origin: rest, atRest: rest))
    }

    @Test("Moved on both axes counts, as on earlier macOS; resting or moved along one axis doesn't")
    func movement() {
        #expect(MissionControlShieldProbe.isDisplaced(isOnScreen: true, origin: CGPoint(x: 400, y: 300), atRest: rest))
        #expect(!MissionControlShieldProbe.isDisplaced(isOnScreen: true, origin: rest, atRest: rest))
        #expect(!MissionControlShieldProbe.isDisplaced(isOnScreen: true, origin: CGPoint(x: 400, y: rest.y), atRest: rest))
    }

    @Test("A drift of up to a point on both axes is still at rest")
    func pointOfDrift() {
        #expect(!MissionControlShieldProbe.isDisplaced(isOnScreen: true, origin: CGPoint(x: rest.x + 1, y: rest.y - 1), atRest: rest))
        #expect(MissionControlShieldProbe.isDisplaced(isOnScreen: true, origin: CGPoint(x: rest.x + 1.5, y: rest.y - 1.5), atRest: rest))
    }

    @Test("Only WindowManager's Exposé shield window counts as the shield")
    func shieldWindow() {
        #expect(MissionControlShieldProbe.isShieldWindow(ownerName: "WindowManager", title: "ExposeShieldWindow"))
        #expect(!MissionControlShieldProbe.isShieldWindow(ownerName: "WindowManager", title: "Desktop"))
        #expect(!MissionControlShieldProbe.isShieldWindow(ownerName: "Dock", title: "ExposeShieldWindow"))
        #expect(!MissionControlShieldProbe.isShieldWindow(ownerName: nil, title: nil))
    }
}

/// Characterization for
/// MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor:),
/// which drops the probe from 10 Hz to 2 Hz only after rest sustained for the
/// full settle window; nil, zero or shorter rest keeps the active rate.
@Suite("Mission Control probe rest back-off")
struct MissionControlProbeBackoffTests {
    @Test("displaced, calibrating, or freshly settled keeps the active rate")
    func unsettledHoldsActiveRate() {
        #expect(MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor: nil) == 0.1)
        #expect(MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor: .zero) == 0.1)
        #expect(MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor: .milliseconds(1900)) == 0.1)
    }

    @Test("rest beyond the settle window drops to the rest rate")
    func settledRestSlowsDown() {
        #expect(MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor: .seconds(2)) == 0.5)
        #expect(MenuBarOverlayPanel.missionControlProbeTickInterval(atRestFor: .seconds(600)) == 0.5)
    }
}

/// Observers and a never-shown overlay use committed activity without changing the live menu bar.
@MainActor
@Suite("Mission Control activity observation", .serialized, .scratchDefaults)
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
