//
//  TestClock.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw

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

extension RevealCaptureSession.SettleClock {
    /// Runs settle waits on the test clock. Its read timer never fires, so a slow runner can't cut a read short.
    static func driven(by clock: TestClock) -> Self {
        Self(
            now: { clock.now },
            sleep: { try? await clock.sleep(for: $0) },
            sleepUntil: { _ in try? await Task.sleep(for: .seconds(3600)) }
        )
    }
}
