//
//  ClickTimeoutEstimator.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// How long to wait for each item to answer a click, learned from its earlier clicks.
///
/// Apps differ tenfold in how fast they open a menu, so one timeout for all either cuts the
/// slow ones off or makes a failed click on a fast one feel broken.
nonisolated struct ClickTimeoutEstimator<Key: Hashable> {
    /// The opening guess for an item with no clicks on record.
    static var defaultTimeout: Duration {
        .milliseconds(350)
    }

    /// The bounds every learned estimate is held to.
    static var range: ClosedRange<Duration> {
        .milliseconds(200) ... .milliseconds(1000)
    }

    private var timeouts: [Key: Duration] = [:]

    func timeout(for key: Key) -> Duration {
        timeouts[key] ?? Self.defaultTimeout
    }

    /// Moves the estimate halfway toward the observed duration and returns the new estimate,
    /// clamped so fast runs cannot starve a slow day and one outlier cannot make clicks feel
    /// broken.
    @discardableResult
    mutating func record(_ observed: Duration, for key: Key) -> Duration {
        let blended = (observed + timeout(for: key)) / 2
        let clamped = blended.clamped(to: Self.range)
        timeouts[key] = clamped
        return clamped
    }

    /// Keeps the estimates from growing without bound over a long session.
    mutating func prune(keeping validKeys: Set<Key>) {
        timeouts = timeouts.filter { validKeys.contains($0.key) }
    }
}
