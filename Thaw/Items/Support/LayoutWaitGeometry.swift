//
//  LayoutWaitGeometry.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// How long to wait for MenuBarAgent to re-sort the bar, and how to tell that it moved.
///
/// A preferred-position write is only a request. The wait that follows needs a deadline and
/// a way to tell a write the agent dropped, where no item shifts, from one it is still
/// working through.
nonisolated enum LayoutWaitGeometry {
    /// Converts the user-facing fulfillment window into a wall-clock deadline,
    /// clamping malformed persisted values to the Layout control's range.
    static func menuBarAgentResortDeadline(
        timeout: TimeInterval,
        from start: ContinuousClock.Instant = ContinuousClock.now
    ) -> ContinuousClock.Instant {
        start + .seconds(clampedResortTimeout(timeout))
    }

    /// Clamps a persisted fulfillment timeout to the Layout control's range.
    static func clampedResortTimeout(_ timeout: TimeInterval) -> TimeInterval {
        timeout.clamped(to: 1 ... 15)
    }

    /// A cheap fingerprint of where every item currently sits. Comparing two of
    /// these tells a preferred-position write MenuBarAgent ignored (every origin
    /// identical) from one it is still working through.
    static func layoutGeometrySignature(_ items: [MenuBarItem]) -> [String: CGFloat] {
        items.reduce(into: [:]) { signature, item in
            signature[item.uniqueIdentifier] = item.bounds.minX
        }
    }

    /// Only an item present in both snapshots that moved at least epsilon
    /// counts, so rows blinking in and out never read as motion.
    static func layoutGeometryChanged(
        from original: [String: CGFloat],
        to current: [String: CGFloat],
        epsilon: CGFloat = 1
    ) -> Bool {
        for (identifier, x) in current {
            guard let previous = original[identifier] else { continue }
            if abs(x - previous) >= epsilon {
                return true
            }
        }
        return false
    }
}
