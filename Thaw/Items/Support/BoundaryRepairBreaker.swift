//
//  BoundaryRepairBreaker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Which items the boundary repair has given up on, and how close each of the others is.
///
/// A repair that keeps failing on one item rewrites its neighbours' order every pass, so after
/// a few failures in a row the item is suppressed and the passes skip it. A suppression lasts
/// for a cooldown, since the item may have been losing to a writer that has since settled.
nonisolated struct BoundaryRepairBreaker<ID: Hashable> {
    struct Outcome: Equatable {
        /// True when this failure reached the limit and the item is now suppressed.
        let suppressed: Bool
        /// Failures in a row including this one, or zero after a repair that worked.
        let trips: Int
    }

    private var trips: [ID: Int] = [:]
    private var suppressedAt: [ID: Date] = [:]

    var suppressedCount: Int {
        suppressedAt.count
    }

    func isSuppressed(_ id: ID) -> Bool {
        suppressedAt[id] != nil
    }

    /// Whether the item is suppressed and its cooldown has not yet passed.
    func suppressionHolds(for id: ID, now: Date, cooldown: TimeInterval) -> Bool {
        suppressedAt[id].map { now.timeIntervalSince($0) < cooldown } ?? false
    }

    func trips(for id: ID) -> Int {
        trips[id] ?? 0
    }

    mutating func addTrip(for id: ID) {
        trips[id, default: 0] += 1
    }

    /// Scores one repair attempt. A repair that worked clears the count; a failure adds to it,
    /// and the one that reaches tripLimit suppresses the item and clears the count.
    @discardableResult
    mutating func record(repaired: Bool, for id: ID, tripLimit: Int, now: Date = Date()) -> Outcome {
        guard !repaired else {
            trips[id] = nil
            return Outcome(suppressed: false, trips: 0)
        }
        let count = trips(for: id) + 1
        guard count >= tripLimit else {
            trips[id] = count
            return Outcome(suppressed: false, trips: count)
        }
        trips[id] = nil
        suppressedAt[id] = now
        return Outcome(suppressed: true, trips: count)
    }

    /// Suppresses an item outright, as for one carried over from an earlier launch.
    mutating func suppress(_ id: ID, at now: Date = Date()) {
        suppressedAt[id] = now
    }

    /// Lets the repair try this item again, from a clean count.
    mutating func rearm(_ id: ID) {
        suppressedAt[id] = nil
        trips[id] = nil
    }

    mutating func rearmAll() {
        suppressedAt.removeAll()
        trips.removeAll()
    }

    /// Re-arms every item whose cooldown has passed, and returns how many.
    @discardableResult
    mutating func rearmExpired(now: Date, cooldown: TimeInterval) -> Int {
        let expired = suppressedAt.filter { now.timeIntervalSince($0.value) >= cooldown }.keys
        expired.forEach { rearm($0) }
        return expired.count
    }

    /// Forgets items that are no longer on the bar.
    mutating func prune(keeping live: Set<ID>) {
        suppressedAt = suppressedAt.filter { live.contains($0.key) }
        trips = trips.filter { live.contains($0.key) }
    }
}
