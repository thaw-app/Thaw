//
//  RevealCaptureSlotTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

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
