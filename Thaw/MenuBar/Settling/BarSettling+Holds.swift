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
    /// How long automatic reorders stand down after a restriction reflow, so its transient geometry
    /// is not mistaken for drift.
    static nonisolated let restrictionReflowWindow = Duration.seconds(10)
    /// How long macOS may take to hide or show the bar after a presentation change.
    static nonisolated let nativeBarChangeWindow = Constants.MenuBarTuning.nativeMenuBarMutationSettle
    /// How long a Thaw press may take to flip the active display before a display switch counts as the user's.
    static nonisolated let thawPressFlipWindow = Duration.seconds(6)

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
        case .savedOrderMirror:
            return isBarQuiet(alsoAfter: lastRestrictionChange) ? nil : .barNotQuiet
        case .barMutation:
            return Self.isWithin(Self.nativeBarChangeWindow, of: lastNativeBarChange, now: now()) ? .nativeBarChanging : nil
        case .layoutReorder:
            return Self.isWithin(Self.restrictionReflowWindow, of: lastRestrictionChange, now: now()) ? .restrictionReflow : nil
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
        isWithin(revealReflowWindow, of: lastRevealChange, now: now)
    }

    /// Strictly inside the window: at its full length the hold has lapsed.
    static nonisolated func isWithin(_ window: Duration, of event: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Bool {
        guard let event else { return false }
        return event.duration(to: now) < window
    }
}
