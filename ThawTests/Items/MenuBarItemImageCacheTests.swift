//
//  MenuBarItemImageCacheTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

private func tag(_ bundleID: String, _ title: String = "Item-0", windowID: CGWindowID? = nil) -> MenuBarItemTag {
    MenuBarItemTag(namespace: .string(bundleID), title: title, windowID: windowID)
}

/// Live refresh ticks every 2.5 s, slows to 4 s once the bar stops changing, and never speeds up a slower setting.
@Suite("Live refresh back-off ladder")
struct MenuBarItemImageCacheBackoffTests {
    @Test(
        "The tick follows the base and the changeless streak",
        arguments: [
            (250, 0, 2500), (250, 4, 2500),
            (250, 5, 4000), (250, 500, 4000), (250, MenuBarItemImageCache.backoffFloorStreak, 4000),
            (5000, 0, 5000), (5000, 30, 5000), (3000, 0, 3000), (3000, 5, 4000),
            (0, 0, 2500), (-50, 70, 4000),
        ]
    )
    func tick(base: Int, changelessStreak: Int, expected: Int) {
        #expect(MenuBarItemImageCache.backedOffTickMilliseconds(baseMilliseconds: base, changelessStreak: changelessStreak) == expected)
    }
}

/// The idle trim keeps glyphs that only a reveal can refill: images of items in a concealed
/// section, matched without the window ID because disk-loaded captures carry none.
@Suite("Idle trim survivors")
struct MenuBarItemImageCacheIdleTrimTests {
    @Test("nothing survives when no section is concealed")
    func nothingConcealedDropsEverything() {
        let cached = [tag("com.a", "A", windowID: 1), tag("com.b", "B", windowID: 2)]
        #expect(MenuBarItemImageCache.idleTrimSurvivors(cachedTags: cached, concealedTags: []).isEmpty)
    }

    @Test("only concealed items' images are kept")
    func keepsConcealedDropsVisible() {
        let visible = tag("com.visible", "V", windowID: 1)
        let hidden = tag("com.hidden", "H", windowID: 2)
        let alwaysHidden = tag("com.always", "AH", windowID: 3)
        let survivors = MenuBarItemImageCache.idleTrimSurvivors(
            cachedTags: [visible, hidden, alwaysHidden],
            concealedTags: [hidden, alwaysHidden]
        )
        #expect(survivors == [hidden, alwaysHidden])
    }

    @Test("a disk-loaded key without a window ID matches its live concealed item")
    func matchesIgnoringWindowID() {
        let diskKey = tag("com.hidden", "H")
        let survivors = MenuBarItemImageCache.idleTrimSurvivors(
            cachedTags: [diskKey],
            concealedTags: [tag("com.hidden", "H", windowID: 42)]
        )
        #expect(survivors == [diskKey])
    }

    @Test("a concealed item with no cached image contributes nothing")
    func concealedWithoutImageIsIgnored() {
        let survivors = MenuBarItemImageCache.idleTrimSurvivors(
            cachedTags: [tag("com.visible", "V", windowID: 1)],
            concealedTags: [tag("com.hidden", "H", windowID: 2)]
        )
        #expect(survivors.isEmpty)
    }
}

/// A memory warning drops the least recently used half of the cache, but not the pictures of
/// hidden items: only a reveal can take those again, and the Thaw Bar shows them (#1606).
@MainActor
@Suite("Memory pressure", .serialized, .scratchDefaults)
struct MenuBarItemImageCacheMemoryPressureTests {
    /// A cache holding tags in order of use, the first least recently used.
    private static func cache(holding tags: [MenuBarItemTag]) throws -> MenuBarItemImageCache {
        let cache = MenuBarItemImageCache(screenIsLocked: { false })
        for tag in tags {
            try cache.setCapture(ItemsFixture.glyph(width: 20, height: 16), for: tag)
            cache.updateAccessOrder(for: tag)
        }
        return cache
    }

    private static func tags(_ count: Int) -> [MenuBarItemTag] {
        (0 ..< count).map { tag("com.example.\($0)", windowID: CGWindowID($0 + 1)) }
    }

    @Test("Without hidden items, the least recently used half goes")
    func dropsLeastRecentlyUsedHalf() throws {
        let tags = Self.tags(4)
        let cache = try Self.cache(holding: tags)

        cache.handleMemoryPressure(concealedTags: [])

        #expect(Set(cache.capturesByTag.keys) == Set(tags.suffix(2)))
    }

    @Test("A hidden item's picture stays even when it was used least recently")
    func keepsHiddenItemPictures() throws {
        // Loaded from disk, so filed without the window ID the live item has.
        let hiddenFromDisk = tag("com.example.hidden")
        let visible = Self.tags(3)
        let cache = try Self.cache(holding: [hiddenFromDisk] + visible)

        cache.handleMemoryPressure(concealedTags: [tag("com.example.hidden", windowID: 9)])

        #expect(Set(cache.capturesByTag.keys) == [hiddenFromDisk, visible[2]])
    }

    @Test("When every picture is a hidden item's, none goes")
    func keepsAllWhenAllHidden() throws {
        let tags = Self.tags(3)
        let cache = try Self.cache(holding: tags)

        cache.handleMemoryPressure(concealedTags: tags)

        #expect(Set(cache.capturesByTag.keys) == Set(tags))
    }
}

@MainActor
@Suite("Capture failure limit", .scratchDefaults)
struct CaptureFailureLimitTests {
    private let cache = MenuBarItemImageCache(screenIsLocked: { false })
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let item = ItemsFixture.item("Failing", bundle: "com.example.failing", x: 1000, y: 4.5, windowID: 7, ownerPID: 999_990, sourcePID: 999_990)

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
