//
//  RevealCaptureTallyTests.swift
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
@Suite("Requested capture tally", .serialized, .scratchDefaults)
struct RevealCaptureTallyTests {
    private typealias Cache = MenuBarItemImageCache

    private func makeItem(_ title: String, instance: Int = 0) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.tally"), title: title, instanceIndex: instance),
            windowID: 501,
            ownerPID: 999_996,
            sourcePID: 999_996,
            bounds: CGRect(x: 1000, y: 4.5, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// Solid ink, pixelWidth wide at scale 2.
    private func glyph(pixelWidth: Int) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil, width: pixelWidth, height: 48, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: 48))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 2)
    }

    /// Runs the commit with an empty tally open, as a requested capture does.
    private func tally(
        _ pass: Cache.CapturePass,
        revealed: [(requested: MenuBarItem, live: MenuBarItem)],
        in cache: Cache
    ) async -> Set<MenuBarItemTag> {
        let tally = RequestedCaptureTally()
        await cache.prewarmSlot.begin(tally: tally)
        defer { cache.prewarmSlot.end() }
        cache.commitCaptureLedger(of: pass, notingRevealed: revealed)
        return tally.tags
    }

    @Test("A new picture of an item with none is tallied")
    func firstPictureIsTallied() async throws {
        let cache = Cache(screenIsLocked: { false })
        let item = makeItem("New")
        var pass = Cache.CapturePass()
        pass.captured[item.tag] = try glyph(pixelWidth: 40)

        #expect(await tally(pass, revealed: [(requested: item, live: item)], in: cache) == [item.tag])
    }

    @Test("A picture the cache keeps over a narrower one is tallied")
    func widerPictureIsTallied() async throws {
        let cache = Cache(screenIsLocked: { false })
        let item = makeItem("Wider")
        try cache.setCapture(glyph(pixelWidth: 20), for: item.tag)
        var pass = Cache.CapturePass()
        pass.captured[item.tag] = try glyph(pixelWidth: 40)

        #expect(await tally(pass, revealed: [(requested: item, live: item)], in: cache) == [item.tag])
    }

    @Test("A picture the cache turns down for the one it has is not tallied")
    func preferredExistingIsNotTallied() async throws {
        let cache = Cache(screenIsLocked: { false })
        let item = makeItem("Narrower")
        try cache.setCapture(glyph(pixelWidth: 40), for: item.tag)
        var pass = Cache.CapturePass()
        pass.captured[item.tag] = try glyph(pixelWidth: 20)

        #expect(await tally(pass, revealed: [(requested: item, live: item)], in: cache) == [])
    }

    @Test("A revealed item the pass got no picture of is not tallied")
    func missingCropIsNotTallied() async {
        let cache = Cache(screenIsLocked: { false })
        let item = makeItem("Missed")

        #expect(await tally(Cache.CapturePass(), revealed: [(requested: item, live: item)], in: cache) == [])
    }

    @Test("The tally names the item that was asked for, not the one the reveal found")
    func requestedTagIsTallied() async throws {
        let cache = Cache(screenIsLocked: { false })
        let requested = makeItem("Rebuilt", instance: 0)
        let live = makeItem("Rebuilt", instance: 1)
        var pass = Cache.CapturePass()
        pass.captured[live.tag] = try glyph(pixelWidth: 40)

        #expect(await tally(pass, revealed: [(requested: requested, live: live)], in: cache) == [requested.tag])
    }

    @Test("Outside a requested capture nothing is tallied, and the ledger still commits")
    func automaticPassRecordsNothing() throws {
        let cache = Cache(screenIsLocked: { false })
        let item = makeItem("Automatic")
        let failed = makeItem("Failed")
        var pass = Cache.CapturePass()
        pass.captured[item.tag] = try glyph(pixelWidth: 40)
        pass.failedCaptureItems = [failed]
        try #require(cache.prewarmSlot.tally == nil)

        cache.commitCaptureLedger(of: pass, notingRevealed: [(requested: item, live: item)])

        #expect(cache.prewarmSlot.tally == nil)
        #expect(cache.failedCapturesLock.withLock { $0[failed.tag]?.failureCount } == 1)
    }
}
