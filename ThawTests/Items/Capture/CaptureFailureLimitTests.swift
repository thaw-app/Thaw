//
//  CaptureFailureLimitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Capture failure limit", .scratchDefaults)
struct CaptureFailureLimitTests {
    private let cache = MenuBarItemImageCache(screenIsLocked: { false })
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let item = MenuBarItem(
        tag: MenuBarItemTag(namespace: .string("com.example.failing"), title: "Failing", instanceIndex: 0),
        windowID: 7,
        ownerPID: 999_990,
        sourcePID: 999_990,
        bounds: CGRect(x: 1000, y: 4.5, width: 24, height: 24),
        title: "Failing",
        isOnScreen: true
    )

    /// Records one failure every interval seconds, count times, and returns the time of the last one.
    @discardableResult
    private func fail(every interval: TimeInterval, times count: Int) -> Date {
        var now = start
        for index in 0 ..< count {
            now = start.addingTimeInterval(interval * Double(index))
            cache.recordCaptureFailure(for: item, at: now)
        }
        return now
    }

    @Test("An item that fails on every pass of the live refresh is set aside, though the passes are under half a second apart")
    func steadyFailuresFasterThanTheSpacingAreSetAside() {
        // The live refresh takes two to three pictures a second: 34 failures in a row were seen without the item ever being set aside.
        let last = fail(every: 0.4, times: 10)
        #expect(cache.shouldSkipCapture(for: item, at: last))
    }

    @Test("Several failures inside one reflow count as one, so a single blip sets nothing aside")
    func oneBlipIsOneStrike() {
        let last = fail(every: 0.1, times: 4)
        #expect(!cache.shouldSkipCapture(for: item, at: last))
    }

    @Test("An item set aside is tried again after the cooldown, and a success clears its failures")
    func cooldownAndSuccessLiftTheLimit() {
        let last = fail(every: 0.6, times: 3)
        #expect(cache.shouldSkipCapture(for: item, at: last))
        #expect(!cache.shouldSkipCapture(for: item, at: last.addingTimeInterval(MenuBarItemImageCache.blacklistCooldownSeconds)))

        fail(every: 0.6, times: 3)
        cache.recordCaptureSuccess(for: item)
        #expect(!cache.shouldSkipCapture(for: item, at: start.addingTimeInterval(2)))
    }
}
