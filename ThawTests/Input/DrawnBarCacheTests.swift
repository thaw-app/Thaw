//
//  DrawnBarCacheTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw
import ThawAXCore

/// A click must find a drawn-bar answer without the pointer having moved, and
/// never one taken before the bar last changed.
@MainActor
@Suite("Drawn bar cache")
struct DrawnBarCacheTests {
    private let bar = [MenuBarAgentWindow.Entry(ownerPID: 7, frame: CGRect(x: 1300, y: 0, width: 38, height: 30))]

    /// A cache whose reads of the bar each say so as they return. The read runs on the main actor
    /// and the cache stores its answer before it next suspends, so once a test has seen a read,
    /// the cache holds what it returned.
    private func makeCache(reading answer: [MenuBarAgentWindow.Entry]?) -> (MenuBarPointerAXCache, AsyncStream<Void>) {
        let (reads, signal) = AsyncStream<Void>.makeStream()
        let cache = MenuBarPointerAXCache(readDrawnBar: {
            signal.yield()
            return answer
        })
        return (cache, reads)
    }

    @Test("A change reads the bar again, with no pointer movement")
    func changeReadsTheBar() async {
        let (cache, stream) = makeCache(reading: bar)
        var reads = stream.makeAsyncIterator()
        cache.drawnBarDidChange()
        _ = await reads.next()
        #expect(cache.drawnBarAnswer()?.entries == bar)
    }

    @Test("An answer from before the last change is not used")
    func olderAnswerIsDropped() async {
        let (cache, stream) = makeCache(reading: bar)
        var reads = stream.makeAsyncIterator()
        cache.drawnBarDidChange()
        _ = await reads.next()
        cache.drawnBarDidChange()
        #expect(cache.drawnBarAnswer() == nil)
        _ = await reads.next()
        #expect(cache.drawnBarAnswer()?.entries == bar)
    }

    @Test("A bar that cannot be read leaves no answer")
    func unreadableBar() async {
        let (cache, stream) = makeCache(reading: nil)
        var reads = stream.makeAsyncIterator()
        cache.drawnBarDidChange()
        _ = await reads.next()
        #expect(cache.drawnBarAnswer() == nil)
    }
}
