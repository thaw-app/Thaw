//
//  Polling.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Runs check now and every interval after, returning its first value, or nil once a check at or past deadline fails.
/// Cancellation is up to sleep: one that throws ends the poll, one that returns early keeps it going.
nonisolated(nonsending) public func poll<T>(
    every interval: Duration,
    deadline: ContinuousClock.Instant,
    now: () -> ContinuousClock.Instant = { .now },
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    _ check: () async throws -> T?
) async rethrows -> T? {
    while true {
        if let value = try await check() {
            return value
        }
        guard now() < deadline else {
            return nil
        }
        try await sleep(interval)
    }
}

/// poll(every:deadline:now:sleep:_:) for a condition: returns whether it held
/// before the deadline passed.
nonisolated(nonsending) public func pollUntil(
    every interval: Duration,
    deadline: ContinuousClock.Instant,
    now: () -> ContinuousClock.Instant = { .now },
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    _ condition: () async throws -> Bool
) async rethrows -> Bool {
    try await poll(every: interval, deadline: deadline, now: now, sleep: sleep) {
        try await condition() ? true : nil
    } ?? false
}
