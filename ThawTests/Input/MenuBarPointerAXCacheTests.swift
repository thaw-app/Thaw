//
//  MenuBarPointerAXCacheTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Synchronization
import Testing
@testable import Thaw
import ThawAXCore

/// The pointer taps read these answers without waiting. The hit-tests here are aimed at a point
/// off every screen and the menu reads at a process that does not exist, so no live element answers.
@MainActor
@Suite("Menu bar pointer AX cache")
struct MenuBarPointerAXCacheTests {
    private static let offScreen = CGPoint(x: -90000, y: -90000)
    private static let absentPID: pid_t = 999_997

    @MainActor
    private final class ReadCounter {
        var reads = 0
    }

    @MainActor
    private final class HitTestRecorder {
        var points: [CGPoint] = []
    }

    /// A clock the test moves by hand, so an age is a fact of the test and not of the machine's speed.
    private final class TestClock: Sendable {
        private let instant = Mutex(ContinuousClock.now)

        var now: ContinuousClock.Instant {
            instant.withLock { $0 }
        }

        func advance(by duration: Duration) {
            instant.withLock { $0 = $0.advanced(by: duration) }
        }
    }

    private func cache(counting counter: ReadCounter, clock: TestClock) -> MenuBarPointerAXCache {
        MenuBarPointerAXCache(readDrawnBar: { @MainActor in
            counter.reads += 1
            return []
        }, now: { clock.now })
    }

    /// Asks until the cache has an answer for location, giving the background hit-test time to land.
    private func waitForForeignWidgetAnswer(_ cache: MenuBarPointerAXCache, at location: CGPoint) async -> Bool? {
        for _ in 0 ..< 200 {
            if let answer = cache.foreignWidget(at: location) {
                return answer
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    @Test("A point off every screen is no foreign widget, and the answer is kept for points near it")
    func freshAnswerIsServedNearby() async {
        let cache = MenuBarPointerAXCache(readDrawnBar: { [] })
        #expect(await cache.isForeignWidget(at: Self.offScreen) == false)
        #expect(cache.foreignWidget(at: Self.offScreen) == false)
        #expect(cache.foreignWidget(at: CGPoint(x: Self.offScreen.x + 2, y: Self.offScreen.y)) == false)
    }

    @Test("A point away from the last answer has none yet, until its own hit-test lands")
    func missStartsAHitTest() async {
        let cache = MenuBarPointerAXCache(readDrawnBar: { [] })
        _ = await cache.isForeignWidget(at: Self.offScreen)
        let elsewhere = CGPoint(x: Self.offScreen.x + 50, y: Self.offScreen.y)
        #expect(cache.foreignWidget(at: elsewhere) == nil)
        #expect(await waitForForeignWidgetAnswer(cache, at: elsewhere) == false)
    }

    @Test("A point asked for while a hit-test runs is answered after it")
    func queuedHitTestRunsNext() async throws {
        let tested = HitTestRecorder()
        let cache = MenuBarPointerAXCache(readDrawnBar: { [] }, hitTest: { @MainActor point in
            tested.points.append(point)
            return false
        })
        let first = CGPoint(x: Self.offScreen.x + 100, y: Self.offScreen.y)
        let second = CGPoint(x: Self.offScreen.x + 200, y: Self.offScreen.y)
        cache.refreshForeignWidget(at: first)
        cache.refreshForeignWidget(at: second)
        // Reading the recorder starts nothing, so only the queue can test the second point.
        let deadline = ContinuousClock.now + .seconds(5)
        while tested.points.count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(tested.points == [first, second])
    }

    @Test("An answer is served until its lifetime ends, and not after")
    func oldAnswerExpires() async {
        let clock = TestClock()
        let cache = MenuBarPointerAXCache(readDrawnBar: { [] }, now: { clock.now })
        _ = await cache.isForeignWidget(at: Self.offScreen)
        clock.advance(by: MenuBarPointerAXCache.foreignWidgetLifetime - .milliseconds(1))
        #expect(cache.foreignWidget(at: Self.offScreen) == false, "an answer a moment short of its lifetime is still served")
        clock.advance(by: .milliseconds(1))
        #expect(cache.foreignWidget(at: Self.offScreen) == nil, "an answer as old as its lifetime is not")
    }

    @Test("An app that is not running has no menu title frames, before or after its read lands")
    func absentAppHasNoMenuFrames() async throws {
        let cache = MenuBarPointerAXCache(readDrawnBar: { [] })
        #expect(cache.applicationMenuFrames(for: Self.absentPID) == nil)
        // A second ask while the first read is out joins it rather than starting another.
        #expect(cache.applicationMenuFrames(for: Self.absentPID) == nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(cache.applicationMenuFrames(for: Self.absentPID) == nil)
    }

    @Test("The bar is not read again moments after the last read, only once that read has aged")
    func recentReadIsNotRepeated() async throws {
        let counter = ReadCounter()
        let clock = TestClock()
        let cache = cache(counting: counter, clock: clock)
        // A read counts only when it is later than the bar's last change, which the cache dates at its creation.
        clock.advance(by: .milliseconds(1))
        cache.refreshDrawnBarIfStale()
        try await waitUntil { counter.reads == 1 }
        // The clock has not moved, so this ask meets the age hold whether or not the read's task has finished.
        cache.refreshDrawnBarIfStale()
        // A read started by mistake would land within this fixed wait.
        try await Task.sleep(for: .milliseconds(50))
        #expect(counter.reads == 1, "an ask moments after a read starts no read")
        clock.advance(by: MenuBarPointerAXCache.drawnBarRefreshAge)
        // The aged ask reads again once the first read's task is gone; an ask that meets the task is ignored, so ask until one takes.
        let deadline = ContinuousClock.now + .seconds(5)
        while counter.reads < 2, ContinuousClock.now < deadline {
            cache.refreshDrawnBarIfStale()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(counter.reads == 2, "an ask after the read has aged reads the bar once more")
    }

    /// Polls condition, which must not start any work, for up to five seconds.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
