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
        try ItemsFixture.glyph(width: pixelWidth, height: 48, scale: 2, color: CGColor(gray: 0, alpha: 1))
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

@MainActor
@Suite("Reveal capture slot")
struct RevealCaptureSlotTests {
    @Test("Passes stand down only while a prewarm holds the slot")
    func standsDownWhileHeld() async {
        let slot = RevealCaptureSlot()
        #expect(!slot.standsDown("test pass"))

        await slot.begin()
        #expect(slot.isHeld)
        #expect(slot.standsDown("test pass"))

        slot.end()
        #expect(!slot.isHeld)
        #expect(!slot.standsDown("test pass"))
    }

    @Test("Each prewarm that takes the slot runs the start hook once, a queued one only when it gets the slot")
    func startHookRunsOnTakingTheSlot() async {
        var starts = 0
        let slot = RevealCaptureSlot { starts += 1 }
        await slot.begin()
        #expect(starts == 1)

        let waiter = Task { @MainActor in await slot.begin() }
        for _ in 0 ..< 5 {
            await Task.yield()
        }
        #expect(starts == 1)

        slot.end()
        await waiter.value
        #expect(starts == 2)
        #expect(slot.isHeld)
        slot.end()
        #expect(!slot.isHeld)
    }

    @Test("Queued prewarms take the slot in arrival order")
    func waitersResumeInOrder() async {
        let slot = RevealCaptureSlot()
        await slot.begin()
        var order: [Int] = []
        let first = Task { @MainActor in
            await slot.begin()
            order.append(1)
        }
        for _ in 0 ..< 5 {
            await Task.yield()
        }
        let second = Task { @MainActor in
            await slot.begin()
            order.append(2)
        }
        for _ in 0 ..< 5 {
            await Task.yield()
        }

        slot.end()
        await first.value
        #expect(order == [1])
        slot.end()
        await second.value
        #expect(order == [1, 2])
        slot.end()
        #expect(!slot.isHeld)
    }

    @Test("A queued request's tally opens only when it holds the slot, and leaves the running one's alone")
    func tallyFollowsTheSlot() async {
        let slot = RevealCaptureSlot()
        let running = RequestedCaptureTally()
        let queued = RequestedCaptureTally()
        await slot.begin(tally: running)
        #expect(slot.tally === running)

        let waiter = Task { @MainActor in
            await slot.begin(tally: queued)
            return slot.tally === queued
        }
        for _ in 0 ..< 5 {
            await Task.yield()
        }
        #expect(slot.tally === running)

        slot.end()
        #expect(await waiter.value)
        slot.end()
        #expect(slot.tally == nil)
    }
}
