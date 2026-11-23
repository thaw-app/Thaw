//
//  RevealedPictureStoreTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins how a revealed item's new picture is weighed against the one cached for it, when that
/// one was loaded from disk and so is filed with no window ID.
@MainActor
@Suite("Revealed picture store", .serialized, .scratchDefaults)
struct RevealedPictureStoreTests {
    private typealias Cache = MenuBarItemImageCache

    private static let namespace = MenuBarItemTag.Namespace.string("com.backblaze.bzbmenu")

    /// The tag a picture loaded from disk is filed under.
    private static let diskTag = MenuBarItemTag(namespace: namespace, title: "Item-0", windowID: nil, instanceIndex: 0)

    /// Backblaze as the bar lists it now.
    private static let item = MenuBarItem(
        tag: MenuBarItemTag(namespace: namespace, title: "Item-0", windowID: 3_341_872_844, instanceIndex: 0),
        windowID: 3_341_872_844,
        ownerPID: 1100,
        sourcePID: 1100,
        bounds: CGRect(x: 890, y: 4.5, width: 24, height: 24),
        title: "Item-0",
        isOnScreen: true
    )

    /// A 24 pt crop at scale 2 with ink in the pixel columns given.
    private static func glyph(inkColumns: Range<Int>, inkRows: Range<Int> = 8 ..< 40) throws -> MenuBarItemGlyphCapture {
        let ink = CGRect(x: inkColumns.lowerBound, y: inkRows.lowerBound, width: inkColumns.count, height: inkRows.count)
        return try ItemsFixture.glyph(width: 48, height: 48, scale: 2, ink: ink)
    }

    /// The flame, whole and centred.
    private static func complete() throws -> MenuBarItemGlyphCapture {
        try glyph(inkColumns: 10 ..< 38)
    }

    /// The flame caught 16 pt left of its frame: its right edge in the first columns, the rest empty.
    private static func cut() throws -> MenuBarItemGlyphCapture {
        try glyph(inkColumns: 0 ..< 5)
    }

    private static func entries(for item: MenuBarItem, in cache: Cache) -> [MenuBarItemTag: MenuBarItemGlyphCapture] {
        cache.capturesByTag.filter { $0.key.matchesIgnoringWindowID(item.tag) }
    }

    @Test("A cut picture doesn't replace a complete one loaded from disk")
    func cutPictureLosesToDiskPicture() throws {
        let cache = Cache(screenIsLocked: { false })
        let kept = try Self.complete()
        cache.setCapture(kept, for: Self.diskTag)

        let changed = try cache.storeRevealedPicture(Self.cut(), of: Self.item, listedWidths: [:])

        #expect(!changed)
        #expect(Self.entries(for: Self.item, in: cache) == [Self.diskTag: kept])
    }

    @Test("A complete picture replaces the one loaded from disk, filed under the item's own tag")
    func completePictureReplacesDiskPicture() throws {
        let cache = Cache(screenIsLocked: { false })
        cache.setCapture(try Self.complete(), for: Self.diskTag)
        let new = try Self.glyph(inkColumns: 12 ..< 36)

        let changed = cache.storeRevealedPicture(new, of: Self.item, listedWidths: [:])

        #expect(changed)
        #expect(Self.entries(for: Self.item, in: cache) == [Self.item.tag: new])
    }

    @Test("A cut picture keeps an earlier build's picture but confirms it, so it isn't retaken again")
    func cutPictureConfirmsEarlierBuildPicture() throws {
        let cache = Cache(screenIsLocked: { false })
        let complete = try Self.complete()
        cache.setCapture(
            MenuBarItemGlyphCapture(cgImage: complete.cgImage, scale: complete.scale, isFromEarlierBuild: true),
            for: Self.diskTag
        )

        let changed = try cache.storeRevealedPicture(Self.cut(), of: Self.item, listedWidths: [:])

        #expect(changed)
        let kept = try #require(cache.capturesByTag[Self.diskTag])
        #expect(kept.cgImage === complete.cgImage)
        #expect(!kept.isFromEarlierBuild)
    }

    @Test("Without Native hiding running, a revealed picture drawn smaller replaces the cached one")
    func smallerPictureWinsWithoutNativeHiding() throws {
        let cache = Cache(screenIsLocked: { false })
        cache.setCapture(try Self.complete(), for: Self.diskTag)
        // Under 80% of the flame's height and width, which Native hiding would take for one still scaling in.
        let smaller = try Self.glyph(inkColumns: 15 ..< 33, inkRows: 14 ..< 34)

        #expect(!cache.revealsRebuildTheBar)
        #expect(cache.storeRevealedPicture(smaller, of: Self.item, listedWidths: [:]))
        #expect(Self.entries(for: Self.item, in: cache) == [Self.item.tag: smaller])
    }

    @Test("An item with no picture gets the new one")
    func firstPictureIsStored() throws {
        let cache = Cache(screenIsLocked: { false })
        let new = try Self.cut()

        #expect(cache.storeRevealedPicture(new, of: Self.item, listedWidths: [:]))
        #expect(cache.capturesByTag[Self.item.tag] == new)
    }

    @Test("A requested capture doesn't count a cut picture as new when the kept one came from disk")
    func tallySkipsCutPicture() async throws {
        let cache = Cache(screenIsLocked: { false })
        cache.setCapture(try Self.complete(), for: Self.diskTag)
        var pass = Cache.CapturePass()
        pass.captured[Self.item.tag] = try Self.cut()
        let tally = RequestedCaptureTally()
        await cache.prewarmSlot.begin(tally: tally)
        defer { cache.prewarmSlot.end() }

        cache.commitCaptureLedger(of: pass, notingRevealed: [(requested: Self.item, live: Self.item)])

        #expect(tally.tags.isEmpty)
    }
}
