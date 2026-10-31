//
//  ActiveMenuBarDisplayWatcherTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@Suite("Active menu bar display watcher")
@MainActor
struct ActiveMenuBarDisplayWatcherTests {
    @MainActor
    final class Probe {
        var displayID: CGDirectDisplayID? = 1
        var changes = 0
    }

    @Test("A move of the active menu bar to another display is reported once")
    func reportsAMove() {
        let probe = Probe()
        let watcher = ActiveMenuBarDisplayWatcher(readDisplayID: { probe.displayID })
        watcher.onChange = { probe.changes += 1 }
        watcher.check()
        #expect(probe.changes == 0)

        probe.displayID = 2
        watcher.check()
        watcher.check()
        #expect(probe.changes == 1)
    }

    @Test("Losing track of the active display is not a move")
    func ignoresUnknown() {
        let probe = Probe()
        let watcher = ActiveMenuBarDisplayWatcher(readDisplayID: { probe.displayID })
        watcher.onChange = { probe.changes += 1 }
        watcher.check()
        probe.displayID = nil
        watcher.check()
        probe.displayID = 1
        watcher.check()
        #expect(probe.changes == 0)
    }

    @Test("A throttled check reads again only after the throttle interval; a plain one always reads")
    func throttledChecks() {
        let probe = Probe()
        var reads = 0
        let watcher = ActiveMenuBarDisplayWatcher(readDisplayID: { reads += 1; return probe.displayID })
        watcher.onChange = { probe.changes += 1 }
        let start = ContinuousClock.now
        watcher.check(throttled: true, now: start)
        probe.displayID = 2
        watcher.check(throttled: true, now: start + .milliseconds(50))
        #expect(reads == 1)
        #expect(probe.changes == 0, "Too soon to read again")

        watcher.check(throttled: true, now: start + .milliseconds(150))
        #expect(reads == 2)
        #expect(probe.changes == 1)

        watcher.check(now: start + .milliseconds(160))
        #expect(reads == 3, "A click always reads")
    }
}
