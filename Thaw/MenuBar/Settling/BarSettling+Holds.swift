//
//  BarSettling+Holds.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension BarSettling {
    /// MenuBarAgent rewrites its whole table 10 s after a new item appears, so the quiet period outlasts that.
    static nonisolated let quietPeriod = Duration.seconds(12)
    /// Generous; observed reflows after a reveal or hide take tens of milliseconds.
    static nonisolated let revealReflowWindow = Duration.milliseconds(500)

    /// Whether the quiet period has passed since the last wake, display invalidation or shift, and since
    /// the given instant when there is one.
    func isBarQuiet(alsoAfter other: ContinuousClock.Instant? = nil) -> Bool {
        Self.isQuiet(now: now(), events: [lastBarDisturbance, other], quietPeriod: Self.quietPeriod)
    }

    /// Why the purpose has to wait, or nil when it may go ahead. The reflow window sits inside the kit's
    /// longer transition, so it only holds the nudge off if the kit clears its flag early.
    func hold(for purpose: Purpose) -> Hold? {
        switch purpose {
        case .agentNudge:
            if Self.isReflowing(lastRevealChange: lastRevealChange, now: now()) {
                return .revealReflow
            }
            return isRevealTransitionActive ? .revealTransition : nil
        }
    }

    static nonisolated func isQuiet(
        now: ContinuousClock.Instant,
        events: [ContinuousClock.Instant?],
        quietPeriod: Duration
    ) -> Bool {
        events.compactMap(\.self).allSatisfy { $0.duration(to: now) >= quietPeriod }
    }

    static nonisolated func isReflowing(lastRevealChange: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Bool {
        guard let lastRevealChange else { return false }
        return lastRevealChange.duration(to: now) < revealReflowWindow
    }
}
