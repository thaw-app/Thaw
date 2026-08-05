//
//  ShareableContentCacheTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers `ShareableContentCache`'s coalescing: a hit inside `maxAge`, a miss
/// once it has elapsed, concurrent callers joining one in-flight fetch, and
/// one caller's cancellation not poisoning another's result.
///
/// Serialized because every case here measures real elapsed time against
/// short `maxAge` budgets. Run concurrently the cases contend for the same
/// executor and the timings stop being reliable, so the suite is kept to one
/// case at a time as it was under XCTest.
@Suite("Shareable content cache", .serialized, .timeLimit(.minutes(1)))
struct ShareableContentCacheTests {
    // MARK: - Hit within maxAge

    @Test("A second call inside maxAge reuses the cached result")
    func hitWithinMaxAgeInvokesFetchOnce() async throws {
        let cache = ShareableContentCache<Int>()
        let invocationCount = Counter()

        @Sendable func fetch() async throws -> Int {
            await invocationCount.increment()
            return 1
        }

        let first = try await cache.content(maxAge: .seconds(60), fetch: fetch)
        let second = try await cache.content(maxAge: .seconds(60), fetch: fetch)

        #expect(first == 1)
        #expect(second == 1)
        let count = await invocationCount.value
        #expect(count == 1, "second call within maxAge should reuse the cached result")
    }

    // MARK: - Miss after expiry

    @Test("A call after maxAge has elapsed fetches again")
    func missAfterExpiryInvokesFetchAgain() async throws {
        let cache = ShareableContentCache<Int>()
        let invocationCount = Counter()

        @Sendable func fetch() async throws -> Int {
            return await invocationCount.increment()
        }

        let first = try await cache.content(maxAge: .milliseconds(100), fetch: fetch)
        try await Task.sleep(for: .milliseconds(300))
        let second = try await cache.content(maxAge: .milliseconds(100), fetch: fetch)

        #expect(first == 1)
        #expect(second == 2)
        let count = await invocationCount.value
        #expect(count == 2, "call after maxAge has elapsed should trigger a fresh fetch")
    }

    // MARK: - Concurrent callers join one in-flight fetch

    @Test("Concurrent callers join the single in-flight fetch")
    func concurrentCallersJoinSingleInFlightFetch() async throws {
        let cache = ShareableContentCache<Int>()
        let invocationCount = Counter()
        let (fetchBegan, fetchBeganContinuation) = AsyncStream.makeStream(of: Void.self)

        @Sendable func slowFetch() async throws -> Int {
            await invocationCount.increment()
            fetchBeganContinuation.yield()
            try await Task.sleep(for: .milliseconds(150))
            return 42
        }

        async let first = cache.content(maxAge: .seconds(60), fetch: slowFetch)
        // Wait until the first call's fetch has actually begun — so it's the
        // one that creates the in-flight task — then join it with two more
        // concurrent callers.
        var began = fetchBegan.makeAsyncIterator()
        _ = await began.next()
        async let second = cache.content(maxAge: .seconds(60), fetch: slowFetch)
        async let third = cache.content(maxAge: .seconds(60), fetch: slowFetch)

        let results = try await [first, second, third]

        #expect(results == [42, 42, 42])
        let count = await invocationCount.value
        #expect(count == 1, "concurrent callers should join the single in-flight fetch rather than starting their own")
    }

    // MARK: - One caller's cancellation doesn't poison the result for the other

    @Test("Cancelling one caller does not affect another")
    func cancellingOneCallerDoesNotAffectAnother() async throws {
        let cache = ShareableContentCache<Int>()
        let invocationCount = Counter()
        let (fetchBegan, fetchBeganContinuation) = AsyncStream.makeStream(of: Void.self)

        @Sendable func slowFetch() async throws -> Int {
            await invocationCount.increment()
            fetchBeganContinuation.yield()
            try await Task.sleep(for: .milliseconds(150))
            return 7
        }

        // The first caller starts the in-flight fetch and will be cancelled
        // before it completes. Wait until its fetch has actually begun so the
        // cancellation is guaranteed to land on an in-flight fetch.
        let cancelledTask = Task<Int, any Error> {
            try await cache.content(maxAge: .seconds(60), fetch: slowFetch)
        }
        var began = fetchBegan.makeAsyncIterator()
        _ = await began.next()
        cancelledTask.cancel()

        // The second caller joins the same in-flight fetch and should still
        // receive the successful result, unaffected by the first caller's
        // cancellation.
        let survivingResult = try await cache.content(maxAge: .seconds(60), fetch: slowFetch)

        #expect(survivingResult == 7)
        let count = await invocationCount.value
        #expect(count == 1, "the surviving caller should not trigger a second fetch")

        // Whether the cancelled caller's own await throws or still observes
        // the shared result is incidental; what matters is that its
        // cancellation must not have cancelled the shared underlying task
        // (verified above via the surviving caller and invocation count).
        _ = try? await cancelledTask.value
    }
}

/// A simple actor-isolated counter for tracking fetch invocations across
/// concurrent tasks in tests.
private actor Counter {
    private(set) var value = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }

    // MARK: - Forced refresh

    /// `captureWindowsImageSCK` re-fetches with `maxAge: .zero` when no
    /// display intersects the windows it is capturing, on the theory that the
    /// cached display set predates a topology change (#794). That recovery
    /// only works if a zero budget genuinely bypasses the cache rather than
    /// treating a just-stored entry as fresh.
    @Test("A zero maxAge always bypasses the cache")
    func zeroMaxAgeAlwaysRefetches() async throws {
        let cache = ShareableContentCache<Int>()
        let invocationCount = Counter()

        @Sendable func fetch() async throws -> Int {
            await invocationCount.increment()
            return await invocationCount.value
        }

        let warm = try await cache.content(maxAge: .seconds(60), fetch: fetch)
        let forced = try await cache.content(maxAge: .zero, fetch: fetch)

        #expect(warm == 1)
        #expect(forced == 2, "a zero budget must not be served from the cache")
        let count = await invocationCount.value
        #expect(count == 2)
    }
}
