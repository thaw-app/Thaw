//
//  ControlResortHold.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Why a re-sort of the control items has to wait for the hiding restriction.
/// MenuBarAgent freezes the rank order while the restriction is applied and the bar reflows, so a re-sort written then is undone or sets off another reflow.
nonisolated enum ControlResortHold: Equatable {
    /// A repair is re-applying the restriction right now.
    case restrictionBeingApplied
    /// The restriction changed recently and the bar is still reflowing.
    case settling(remaining: Duration)

    /// What the hold is judged from.
    nonisolated struct Signal {
        let restrictionChangedAt: ContinuousClock.Instant?
        let isRestrictionBeingApplied: Bool
        let settleWindow: Duration
    }

    private static let diagLog = DiagLog(category: "ControlResortHold")

    /// How long past the hold a deferred re-sort waits, so it lands on a settled bar.
    static let margin = Duration.milliseconds(200)

    /// The hold in force, or nil when a control re-sort may run.
    static func current(_ signal: Signal, now: ContinuousClock.Instant) -> Self? {
        if signal.isRestrictionBeingApplied {
            return .restrictionBeingApplied
        }
        guard let changedAt = signal.restrictionChangedAt else { return nil }
        let elapsed = changedAt.duration(to: now)
        guard elapsed < signal.settleWindow else { return nil }
        return .settling(remaining: signal.settleWindow - elapsed)
    }

    /// The wait before a re-sort, stretched so it ends after any hold in force.
    static func debounce(_ debounce: Duration, hold: Self?) -> Duration {
        guard let hold else { return debounce }
        return max(debounce, hold.retryAfter)
    }

    /// The reason, for the log.
    var reason: String {
        switch self {
        case .restrictionBeingApplied:
            "the hiding restriction is being applied"
        case let .settling(remaining):
            "the bar is settling after a hiding change (\(remaining) left)"
        }
    }

    /// When to try the re-sort again.
    var retryAfter: Duration {
        switch self {
        case .restrictionBeingApplied:
            .seconds(1)
        case let .settling(remaining):
            remaining + Self.margin
        }
    }

    /// The debounce a pass waits before it re-sorts, logging when a hold stretches it.
    static func debounce(
        _ debounce: Duration,
        for work: String,
        _ signal: Signal?,
        now: ContinuousClock.Instant = .now
    ) -> Duration {
        let hold = signal.flatMap { current($0, now: now) }
        let wait = Self.debounce(debounce, hold: hold)
        if let hold, wait > debounce {
            diagLog.debug("\(work): waiting \(wait) because \(hold.reason)")
        }
        return wait
    }

    /// Whether a pass may re-sort the controls now, logging why when it may not.
    static func allowsResort(for work: String, _ signal: Signal, now: ContinuousClock.Instant = .now) -> Bool {
        guard let hold = current(signal, now: now) else { return true }
        diagLog.debug("\(work): skipping, \(hold.reason)")
        return false
    }
}

extension ControlResortHold.Signal {
    /// The restriction as the item manager last saw it.
    @MainActor
    init(of manager: MenuBarItemManager) {
        self.init(
            restrictionChangedAt: manager.lastRestrictionChangeTimestamp,
            isRestrictionBeingApplied: manager.isRunningPostRestrictionRepair,
            settleWindow: MenuBarItemManager.restrictionChangeLayoutSettleWindow
        )
    }
}
