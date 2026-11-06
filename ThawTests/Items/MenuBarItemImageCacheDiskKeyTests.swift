//
//  MenuBarItemImageCacheDiskKeyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Live tags can share a disk tagIdentifier; collapse by recency to prevent duplicate-key traps on the save queue.
@MainActor
@Suite("Disk-persistable captures")
struct MenuBarItemImageCacheDiskKeyTests {
    private static func tag(
        _ bundleID: String,
        _ title: String,
        windowID: CGWindowID? = nil
    ) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string(bundleID), title: title, windowID: windowID)
    }

    /// Scale distinguishes captures; opaque 20pt fixtures avoid blank-image misses and minimumTrustedGlyphWidth's chevron-bleed rejection.
    private static func capture(scale: CGFloat) -> MenuBarItemGlyphCapture {
        let width = Int(20 * scale)
        let height = Int(16 * scale)
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return MenuBarItemGlyphCapture(cgImage: context.makeImage()!, scale: scale)
    }

    @Test("distinct identifiers all survive")
    func distinctIdentifiersSurvive() {
        let a = Self.tag("com.a", "A", windowID: 1)
        let b = Self.tag("com.b", "B", windowID: 2)
        let survivors = MenuBarItemImageCache.diskPersistableCaptures(
            capturesByTag: [a: Self.capture(scale: 1), b: Self.capture(scale: 2)],
            accessTimestamps: [a: 1, b: 2]
        )

        #expect(Set(survivors.keys) == [a, b])
        #expect(Set(survivors.keys.map(\.tagIdentifier)).count == survivors.count)
    }

    @Test("one status item read across two windows collapses to the fresher read")
    func windowIDRespawnCollapses() {
        let stale = Self.tag("com.a", "A", windowID: 1)
        let fresh = Self.tag("com.a", "A", windowID: 2)
        #expect(stale != fresh)
        #expect(stale.tagIdentifier == fresh.tagIdentifier)

        let survivors = MenuBarItemImageCache.diskPersistableCaptures(
            capturesByTag: [stale: Self.capture(scale: 1), fresh: Self.capture(scale: 3)],
            accessTimestamps: [stale: 7, fresh: 9]
        )

        #expect(Array(survivors.keys) == [fresh])
        #expect(survivors[fresh]?.scale == 3)
    }

    /// Unequal live metric tags can canonicalize to the same disk identifier.
    @Test("two ticks of a metric title collapse to one entry")
    func metricTitleTicksCollapse() {
        let earlier = Self.tag("com.bjango.istatmenus-setapp.status", "CPU 42%", windowID: 1)
        let later = Self.tag("com.bjango.istatmenus-setapp.status", "CPU 43%", windowID: 1)
        #expect(earlier != later)
        #expect(earlier.tagIdentifier == later.tagIdentifier)

        let survivors = MenuBarItemImageCache.diskPersistableCaptures(
            capturesByTag: [earlier: Self.capture(scale: 1), later: Self.capture(scale: 2)],
            accessTimestamps: [earlier: 4, later: 5]
        )

        #expect(Array(survivors.keys) == [later])
        #expect(survivors[later]?.scale == 2)
    }

    /// Untouched entries lack timestamps but still need one deterministic survivor per save.
    @Test("a tie without timestamps resolves to the newer window, deterministically")
    func tieResolvesToNewerWindow() {
        let older = Self.tag("com.a", "A", windowID: 10)
        let newer = Self.tag("com.a", "A", windowID: 20)

        for _ in 0 ..< 32 {
            let survivors = MenuBarItemImageCache.diskPersistableCaptures(
                capturesByTag: [older: Self.capture(scale: 1), newer: Self.capture(scale: 2)],
                accessTimestamps: [:]
            )
            #expect(Array(survivors.keys) == [newer])
        }
    }

    @Test("an empty cache collapses to nothing")
    func emptyStaysEmpty() {
        #expect(
            MenuBarItemImageCache.diskPersistableCaptures(
                capturesByTag: [:], accessTimestamps: [:]
            ).isEmpty
        )
    }

    // MARK: Gap fill

    /// Disk-loaded tags lack window IDs, so exact-tag gap checks miss live entries and create duplicates.
    @Test("an item the live pass already captured is not a gap")
    func liveCaptureIsNotAGap() {
        let live = Self.tag("com.a", "A", windowID: 42)
        let fromDisk = Self.tag("com.a", "A", windowID: nil)
        #expect(live != fromDisk)
        #expect(live.tagIdentifier == fromDisk.tagIdentifier)

        let selections = MenuBarItemImageCache.diskGapFillSelections(
            loaded: [fromDisk: Self.capture(scale: 1)],
            cachedTags: [live]
        )

        #expect(selections.isEmpty)
    }

    @Test("an item with no live capture is filled from disk")
    func missingItemIsFilled() {
        let live = Self.tag("com.a", "A", windowID: 42)
        let absent = Self.tag("com.b", "B", windowID: nil)

        let selections = MenuBarItemImageCache.diskGapFillSelections(
            loaded: [absent: Self.capture(scale: 2)],
            cachedTags: [live]
        )

        #expect(Array(selections.keys) == [absent])
        #expect(selections[absent]?.scale == 2)
    }

    @Test("an empty live cache takes every disk entry")
    func coldCacheTakesEverything() {
        let a = Self.tag("com.a", "A", windowID: nil)
        let b = Self.tag("com.b", "B", windowID: nil)

        let selections = MenuBarItemImageCache.diskGapFillSelections(
            loaded: [a: Self.capture(scale: 1), b: Self.capture(scale: 2)],
            cachedTags: []
        )

        #expect(Set(selections.keys) == [a, b])
    }

    /// Loaded entries must still collapse to one entry per identifier before saving.
    @Test("load then save never produces a duplicate identifier")
    func loadThenSaveStaysUnique() {
        let live = Self.tag("com.a", "A", windowID: 42)
        var cache = [live: Self.capture(scale: 1)]

        let selections = MenuBarItemImageCache.diskGapFillSelections(
            loaded: [
                Self.tag("com.a", "A", windowID: nil): Self.capture(scale: 9),
                Self.tag("com.b", "B", windowID: nil): Self.capture(scale: 2),
            ],
            cachedTags: cache.keys
        )
        for (tag, image) in selections {
            cache[tag] = image
        }

        #expect(cache.count == 2)
        let persistable = MenuBarItemImageCache.diskPersistableCaptures(
            capturesByTag: cache,
            accessTimestamps: [:]
        )
        #expect(persistable.count == Set(persistable.keys.map(\.tagIdentifier)).count)
        // The live pixels won; the stale disk copy never displaced them.
        #expect(persistable[live]?.scale == 1)
    }

    @Test("Disk gap filling registers timestamps before any consumer reads the images")
    func diskMergeTracksUnreadCaptures() {
        let cache = MenuBarItemImageCache()
        let first = Self.tag("com.a", "A")
        let second = Self.tag("com.b", "B")

        #expect(cache.mergeDiskCaptures([first: Self.capture(scale: 1)]) == 1)
        #expect(cache.mergeDiskCaptures([second: Self.capture(scale: 2)]) == 1)
        #expect(cache.capturesByTag.count == 2)
        #expect(cache.lruEntryCount == cache.capturesByTag.count)
    }

    @Test("A disk reload preserves existing captures without creating extra timestamps")
    func diskReloadDoesNotOverwriteOrDuplicate() {
        let cache = MenuBarItemImageCache()
        let live = Self.tag("com.a", "A", windowID: 42)
        let disk = Self.tag("com.a", "A")
        cache.mergeDiskCaptures([live: Self.capture(scale: 1)])

        #expect(cache.mergeDiskCaptures([disk: Self.capture(scale: 2)]) == 0)
        #expect(cache.capturesByTag[live]?.scale == 1)
        #expect(cache.capturesByTag[disk] == nil)
        #expect(cache.lruEntryCount == 1)
    }

    // MARK: Resolution

    /// The section gate must use the per-item fallback for disk glyphs without window IDs to avoid needless re-reveals.
    @Test("a glyph cached without a window ID resolves for a live tag")
    func resolvesAcrossWindowID() {
        let live = Self.tag("com.a", "A", windowID: 42)
        let fromDisk = Self.tag("com.a", "A", windowID: nil)

        let resolved = MenuBarItemImageCache.cachedCapture(
            for: live,
            in: [fromDisk: Self.capture(scale: 2)]
        )

        #expect(resolved?.tag == fromDisk)
        #expect(resolved?.capture.scale == 2)
        // The gate is what decides whether to reveal the section at all.
        #expect(
            MenuBarItemImageCache.prewarmNeedsCapture(
                cachedImage: resolved?.capture,
                wouldAttemptCapture: true
            ) == false
        )
    }

    @Test("an exact match is preferred over a window-ID-insensitive one")
    func exactMatchWins() {
        let live = Self.tag("com.a", "A", windowID: 42)
        let fromDisk = Self.tag("com.a", "A", windowID: nil)

        let resolved = MenuBarItemImageCache.cachedCapture(
            for: live,
            in: [live: Self.capture(scale: 1), fromDisk: Self.capture(scale: 2)]
        )

        #expect(resolved?.tag == live)
        #expect(resolved?.capture.scale == 1)
    }

    @Test("an item with nothing cached still needs a capture")
    func genuineMissStillReveals() {
        let live = Self.tag("com.a", "A", windowID: 42)
        let unrelated = Self.tag("com.b", "B", windowID: nil)

        let resolved = MenuBarItemImageCache.cachedCapture(
            for: live,
            in: [unrelated: Self.capture(scale: 1)]
        )

        #expect(resolved == nil)
        #expect(
            MenuBarItemImageCache.prewarmNeedsCapture(
                cachedImage: resolved?.capture,
                wouldAttemptCapture: true
            )
        )
    }

    @Test("a glyph loaded from disk counts as present, so one gap does not recapture the section")
    func diskLoadedGlyphIsKept() {
        let wide = Self.capture(scale: 2)
        #expect(
            !MenuBarItemImageCache.prewarmNeedsCapture(
                cachedImage: wide,
                wouldAttemptCapture: true
            )
        )
    }

    @Test("a concealed item's saved glyph outlives the unclassified age")
    func concealedEntryKeepsStableAge() {
        let store = MenuBarItemImageCacheDiskStore()
        #expect(store.diskCacheTTL(for: nil) < 60)
        #expect(
            store.diskCacheTTL(for: nil, wasConcealed: true)
                == MenuBarItemImageCacheDiskStore.stableCacheAgeSeconds
        )
    }
}
