//
//  ShareableContentCacheTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class ShareableContentCacheTests: XCTestCase {
    // MARK: - Hit within maxAge

    func testHitWithinMaxAgeInvokesFetchOnce() async throws {
        let cache = ShareableContentCache<Int>()
        let invocationCount = Counter()

        @Sendable func fetch() async throws -> Int {
            await invocationCount.increment()
            return 1
        }

        let first = try await cache.content(maxAge: .seconds(60), fetch: fetch)
        let second = try await cache.content(maxAge: .seconds(60), fetch: fetch)

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
        let count = await invocationCount.value
        XCTAssertEqual(count, 1, "second call within maxAge should reuse the cached result")
    }

    // MARK: - Miss after expiry

    func testMissAfterExpiryInvokesFetchAgain() async throws {
        let cache = ShareableContentCache<Int>()
        let invocationCount = Counter()

        @Sendable func fetch() async throws -> Int {
            let n = await invocationCount.increment()
            return n
        }

        let first = try await cache.content(maxAge: .milliseconds(20), fetch: fetch)
        try await Task.sleep(for: .milliseconds(60))
        let second = try await cache.content(maxAge: .milliseconds(20), fetch: fetch)

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        let count = await invocationCount.value
        XCTAssertEqual(count, 2, "call after maxAge has elapsed should trigger a fresh fetch")
    }

    // MARK: - Concurrent callers join one in-flight fetch

    func testConcurrentCallersJoinSingleInFlightFetch() async throws {
        let cache = ShareableContentCache<Int>()
        let invocationCount = Counter()

        @Sendable func slowFetch() async throws -> Int {
            await invocationCount.increment()
            try await Task.sleep(for: .milliseconds(150))
            return 42
        }

        async let first = cache.content(maxAge: .seconds(60), fetch: slowFetch)
        // Give the first call a head start so it's the one that creates the
        // in-flight task, then join it with two more concurrent callers.
        try await Task.sleep(for: .milliseconds(20))
        async let second = cache.content(maxAge: .seconds(60), fetch: slowFetch)
        async let third = cache.content(maxAge: .seconds(60), fetch: slowFetch)

        let results = try await [first, second, third]

        XCTAssertEqual(results, [42, 42, 42])
        let count = await invocationCount.value
        XCTAssertEqual(count, 1, "concurrent callers should join the single in-flight fetch rather than starting their own")
    }

    // MARK: - One caller's cancellation doesn't poison the result for the other

    func testCancellingOneCallerDoesNotAffectAnother() async throws {
        let cache = ShareableContentCache<Int>()
        let invocationCount = Counter()

        @Sendable func slowFetch() async throws -> Int {
            await invocationCount.increment()
            try await Task.sleep(for: .milliseconds(150))
            return 7
        }

        // The first caller starts the in-flight fetch and will be cancelled
        // before it completes.
        let cancelledTask = Task<Int, any Error> {
            try await cache.content(maxAge: .seconds(60), fetch: slowFetch)
        }
        try await Task.sleep(for: .milliseconds(20))
        cancelledTask.cancel()

        // The second caller joins the same in-flight fetch and should still
        // receive the successful result, unaffected by the first caller's
        // cancellation.
        let survivingResult = try await cache.content(maxAge: .seconds(60), fetch: slowFetch)

        XCTAssertEqual(survivingResult, 7)
        let count = await invocationCount.value
        XCTAssertEqual(count, 1, "the surviving caller should not trigger a second fetch")

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
}
