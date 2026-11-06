//
//  MissionControlShieldProbeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// The probe's polling, run against its own invisible one-point window. Ticks run on the main
/// run loop, which a busy suite can hold up, so tests wait for the ticks rather than a fixed time.
@Suite("Mission Control shield probe polling", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct MissionControlShieldProbeTests {
    private func wait(_ duration: Duration) async {
        try? await Task.sleep(for: duration)
    }

    @Test("Polling that is not wanted never reads the window or reports Mission Control")
    func unwantedPollStaysQuiet() async throws {
        let probe = try MissionControlShieldProbe(owningScreen: #require(NSScreen.screens.first))
        var asked = 0
        let (stream, tick) = AsyncStream.makeStream(of: Void.self)
        probe.shouldRun = {
            asked += 1
            tick.yield()
            return false
        }
        probe.updatePolling(isWanted: true)
        probe.updatePolling(isWanted: true)
        var ticked = stream.makeAsyncIterator()
        await ticked.next()
        #expect(asked > 0, "each tick asks whether to run")
        #expect(!probe.isActive)
        probe.updatePolling(isWanted: false)
        probe.updatePolling(isWanted: false)
        let askedAfterStop = asked
        await wait(.milliseconds(300))
        #expect(asked <= askedAfterStop + 2, "a stopped poll asks at most a tick or two more")
        probe.close()
    }

    @Test("A probe window that is never ordered in cannot be read, so the probe stays inactive")
    func unorderedWindow() async throws {
        let probe = try MissionControlShieldProbe(owningScreen: #require(NSScreen.screens.first))
        probe.shouldRun = { true }
        probe.updatePolling(isWanted: true)
        await wait(.milliseconds(350))
        #expect(!probe.isActive)
        probe.reset()
        probe.close()
    }

    @Test("A probe left where it was put never reports Mission Control")
    func restingProbe() async throws {
        let probe = try MissionControlShieldProbe(owningScreen: #require(NSScreen.screens.first))
        var asked = 0
        let (stream, tick) = AsyncStream.makeStream(of: Void.self)
        probe.shouldRun = {
            asked += 1
            tick.yield()
            return true
        }
        // The window is fully transparent, one point square and ignores the mouse.
        probe.start()
        probe.updatePolling(isWanted: true)
        var ticked = stream.makeAsyncIterator()
        await ticked.next()
        await ticked.next()
        // Long enough to calibrate and pass the two-second settle window.
        await wait(.milliseconds(2600))
        #expect(asked > 1)
        #expect(!probe.isActive, "no Expose shield is up during the test")
        probe.close()
    }
}
