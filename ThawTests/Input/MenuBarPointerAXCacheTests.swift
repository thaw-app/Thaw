//
//  MenuBarPointerAXCacheTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
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

    private func cache(counting counter: ReadCounter) -> MenuBarPointerAXCache {
        MenuBarPointerAXCache(readDrawnBar: { @MainActor in
            counter.reads += 1
            return []
        })
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
    func queuedHitTestRunsNext() async {
        let cache = MenuBarPointerAXCache(readDrawnBar: { [] })
        let first = CGPoint(x: Self.offScreen.x + 100, y: Self.offScreen.y)
        let second = CGPoint(x: Self.offScreen.x + 200, y: Self.offScreen.y)
        cache.refreshForeignWidget(at: first)
        cache.refreshForeignWidget(at: second)
        // Only the queued hit-test can leave an answer for the second point; asking
        // before then would start a hit-test of its own.
        try? await Task.sleep(for: .milliseconds(500))
        #expect(cache.foreignWidget(at: second) == false)
    }

    @Test("An answer older than its lifetime is not served")
    func oldAnswerExpires() async throws {
        let cache = MenuBarPointerAXCache(readDrawnBar: { [] })
        _ = await cache.isForeignWidget(at: Self.offScreen)
        try await Task.sleep(for: .milliseconds(800))
        #expect(cache.foreignWidget(at: Self.offScreen) == nil)
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
        let cache = cache(counting: counter)
        cache.refreshDrawnBarIfStale()
        for _ in 0 ..< 100 where counter.reads == 0 {
            await Task.yield()
        }
        #expect(counter.reads == 1)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        cache.refreshDrawnBarIfStale()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(counter.reads == 1)
        try await Task.sleep(for: .milliseconds(350))
        cache.refreshDrawnBarIfStale()
        for _ in 0 ..< 100 where counter.reads == 1 {
            await Task.yield()
        }
        #expect(counter.reads == 2)
    }
}
