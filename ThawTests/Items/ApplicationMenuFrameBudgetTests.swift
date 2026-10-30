//
//  ApplicationMenuFrameBudgetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// The app-menu frame is read from the foreground app on the main actor, so a slow or huge
/// app must not hold it: the read gives up and reports no frame.
@Suite("Application menu frame budget")
struct ApplicationMenuFrameBudgetTests {
    private let titles = [CGRect(x: 10, y: 0, width: 34, height: 30), CGRect(x: 43, y: 0, width: 72, height: 30)]

    @Test("Within the budget the menu titles' frames are joined")
    func joinsWithinBudget() {
        let union = AXHelpers.boundedMenuFrameUnion(titles, budget: .milliseconds(300)) { $0 }
        #expect(union == CGRect(x: 10, y: 0, width: 105, height: 30))
    }

    @Test("Children that aren't menu titles are left out")
    func skipsOtherChildren() {
        let union = AXHelpers.boundedMenuFrameUnion(titles + [CGRect(x: 900, y: 0, width: 30, height: 30)], budget: .milliseconds(300)) {
            $0.minX < 500 ? $0 : nil
        }
        #expect(union == CGRect(x: 10, y: 0, width: 105, height: 30))
    }

    @Test("More children than the limit give no frame, before any is read")
    func tooManyChildren() {
        var reads = 0
        let many = Array(repeating: titles[0], count: AXHelpers.applicationMenuChildLimit + 1)
        let union = AXHelpers.boundedMenuFrameUnion(many, budget: .milliseconds(300)) { reads += 1; return $0 }
        #expect(union == nil)
        #expect(reads == 0)
    }

    @Test("A read that runs past the budget gives no frame and stops reading")
    func slowAppRunsOut() {
        let clock = ManualClock()
        var reads = 0
        let union = AXHelpers.boundedMenuFrameUnion(titles + titles, budget: .milliseconds(300), now: clock.now) {
            reads += 1
            clock.advance(by: .milliseconds(250))
            return $0
        }
        #expect(union == nil)
        #expect(reads == 2, "the third title isn't asked for once the budget is spent")
    }
}

private final class ManualClock {
    private var instant = ContinuousClock.now
    func now() -> ContinuousClock.Instant {
        instant
    }

    func advance(by duration: Duration) {
        instant += duration
    }
}
