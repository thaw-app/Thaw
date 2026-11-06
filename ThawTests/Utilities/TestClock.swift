//
//  TestClock.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// A monotonic clock a test moves by hand. Its sleep moves it on by the duration and yields, so code
/// polling on it runs to its end without real time passing.
@MainActor
final class TestClock {
    var now = ContinuousClock.now

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        now = now.advanced(by: duration)
        await Task.yield()
    }
}
