//
//  IgnoredPreferredWritesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("An item whose writes the agent ignores goes straight to the drag")
struct IgnoredPreferredWritesTests {
    @Test("Two unverified writes in a row skip the write; a verified one restores it")
    func strikesAndReset() {
        var writes = IgnoredPreferredWrites()
        let helper = "helper:Item-0"

        writes.noteUnverified(helper)
        #expect(!writes.skipsWrite(for: helper))
        writes.noteUnverified(helper)
        #expect(writes.skipsWrite(for: helper))
        #expect(!writes.skipsWrite(for: "other:Item-0"))

        writes.noteVerified(helper)
        #expect(!writes.skipsWrite(for: helper))
    }

    @Test("A verified write between unverified ones restarts the count")
    func verifiedWriteBreaksTheRun() {
        var writes = IgnoredPreferredWrites()
        let item = "app:Item-0"

        writes.noteUnverified(item)
        writes.noteVerified(item)
        writes.noteUnverified(item)
        #expect(!writes.skipsWrite(for: item))
    }

    @Test("After the retry interval the write gets one more try")
    func writeIsRetriedLater() {
        var writes = IgnoredPreferredWrites()
        let item = "helper:Item-0"
        let start = ContinuousClock.now

        writes.noteUnverified(item, at: start)
        writes.noteUnverified(item, at: start)
        #expect(writes.skipsWrite(for: item, at: start + IgnoredPreferredWrites.retryAfter - .seconds(1)))
        #expect(!writes.skipsWrite(for: item, at: start + IgnoredPreferredWrites.retryAfter))
    }

    @Test("A retry the agent ignores too puts the item straight back on the drag")
    func failedRetrySkipsAgain() {
        var writes = IgnoredPreferredWrites()
        let item = "helper:Item-0"
        let start = ContinuousClock.now
        writes.noteUnverified(item, at: start)
        writes.noteUnverified(item, at: start)
        let retry = start + IgnoredPreferredWrites.retryAfter

        writes.noteUnverified(item, at: retry)
        #expect(writes.skipsWrite(for: item, at: retry + .seconds(1)))
        #expect(!writes.skipsWrite(for: item, at: retry + IgnoredPreferredWrites.retryAfter))
    }

    @Test("A retry the agent honours clears the record")
    func honouredRetryClears() {
        var writes = IgnoredPreferredWrites()
        let item = "helper:Item-0"
        let start = ContinuousClock.now
        writes.noteUnverified(item, at: start)
        writes.noteUnverified(item, at: start)
        let retry = start + IgnoredPreferredWrites.retryAfter

        writes.noteVerified(item)
        writes.noteUnverified(item, at: retry)
        #expect(!writes.skipsWrite(for: item, at: retry))
    }
}
