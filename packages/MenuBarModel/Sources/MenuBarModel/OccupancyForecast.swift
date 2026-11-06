//
//  OccupancyForecast.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

// MARK: - OccupancyForecast

/// The projected result of fitting menu bar items into a display's usable
/// width. A forecast never acts: it names the items the bar will clip, and a
/// wrong forecast must degrade to plain clipping with nothing corrupted.
public struct OccupancyForecast: Sendable, Equatable {
    public let capacity: CGFloat

    /// Zero when the outcome is indeterminate.
    public let projectedOccupancy: CGFloat

    public let outcome: Outcome

    public init(capacity: CGFloat, projectedOccupancy: CGFloat, outcome: Outcome) {
        self.capacity = capacity
        self.projectedOccupancy = projectedOccupancy
        self.outcome = outcome
    }
}

public extension OccupancyForecast {
    enum Outcome: Sendable, Equatable {
        case fits

        /// Leftmost first: items grow leftward, so the bar loses that one first.
        case ejects([Ejection])

        /// Distinct from fits, so an unanswerable question never reads as "no problem".
        case indeterminate(IndeterminateReason)
    }

    struct Ejection: Sendable, Equatable {
        /// MenuBarItem.uniqueIdentifier.
        public let identifier: String

        /// Points past capacity; largest for the leftmost ejection.
        public let overflow: CGFloat

        public init(identifier: String, overflow: CGFloat) {
            self.identifier = identifier
            self.overflow = overflow
        }
    }

    enum IndeterminateReason: Sendable, Equatable {
        /// An item has never been seen visible. Its width is never guessed.
        case unknownWidths

        /// Zero or negative: headless, clamshell, or mid-reconfiguration.
        case invalidCapacity

        /// A width or edge was NaN or infinite.
        case invalidGeometry
    }
}

// MARK: - OccupancyPlanner

/// Projects whether menu bar items fit the space available. Pure: the caller
/// measures capacity and supplies last-seen widths.
public enum OccupancyPlanner {
    public struct ProjectedItem: Sendable, Equatable {
        /// MenuBarItem.uniqueIdentifier.
        public let identifier: String

        /// Nil when never seen visible, which makes the whole forecast indeterminate.
        public let width: CGFloat?

        /// Used only for ordering, so a concealed item's stale edge is fine.
        public let leadingEdge: CGFloat

        public init(identifier: String, width: CGFloat?, leadingEdge: CGFloat) {
            self.identifier = identifier
            self.width = width
            self.leadingEdge = leadingEdge
        }
    }

    /// Accumulates from the right, as status items grow, so the clipped items
    /// are the leftward tail.
    public static func forecast(
        items: [ProjectedItem],
        capacity: CGFloat
    ) -> OccupancyForecast {
        guard capacity.isFinite, !capacity.isNaN else {
            return OccupancyForecast(
                capacity: capacity,
                projectedOccupancy: 0,
                outcome: .indeterminate(.invalidGeometry)
            )
        }
        guard capacity > 0 else {
            return OccupancyForecast(
                capacity: capacity,
                projectedOccupancy: 0,
                outcome: .indeterminate(.invalidCapacity)
            )
        }
        // An empty bar fits, never indeterminate.
        guard !items.isEmpty else {
            return OccupancyForecast(
                capacity: capacity,
                projectedOccupancy: 0,
                outcome: .fits
            )
        }
        let hasInvalidGeometry = items.contains { item in
            !item.leadingEdge.isFinite
                || item.leadingEdge.isNaN
                || (item.width.map { !$0.isFinite || $0.isNaN || $0 < 0 } ?? false)
        }
        guard !hasInvalidGeometry else {
            return OccupancyForecast(
                capacity: capacity,
                projectedOccupancy: 0,
                outcome: .indeterminate(.invalidGeometry)
            )
        }
        guard items.allSatisfy({ $0.width != nil }) else {
            return OccupancyForecast(
                capacity: capacity,
                projectedOccupancy: 0,
                outcome: .indeterminate(.unknownWidths)
            )
        }

        let total = items.reduce(CGFloat.zero) { $0 + ($1.width ?? 0) }
        guard total > capacity else {
            return OccupancyForecast(
                capacity: capacity,
                projectedOccupancy: total,
                outcome: .fits
            )
        }

        // The identifier tie-break keeps the order total when two items share
        // a leading edge during a reflow.
        let rightToLeft = items.sorted { lhs, rhs in
            if lhs.leadingEdge == rhs.leadingEdge {
                return lhs.identifier > rhs.identifier
            }
            return lhs.leadingEdge > rhs.leadingEdge
        }

        var running = CGFloat.zero
        var ejections = [OccupancyForecast.Ejection]()
        for item in rightToLeft {
            running += item.width ?? 0
            guard running > capacity else { continue }
            ejections.append(
                OccupancyForecast.Ejection(
                    identifier: item.identifier,
                    overflow: running - capacity
                )
            )
        }

        return OccupancyForecast(
            capacity: capacity,
            projectedOccupancy: total,
            outcome: .ejects(ejections.reversed())
        )
    }
}
