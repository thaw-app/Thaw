//
//  ControlItemSeating.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Where Thaw's own control items belong in the host's weight table when the
/// members around them are not Thaw's to move.
///
/// In manual arrangement Thaw may only write its own dividers' weights, so
/// members are fixed anchors and a divider takes a free weight between them.
public enum ControlItemSeating {
    /// The spacing a full ladder uses, so a control seated past the end of the
    /// order lands where a later respace would expect it.
    public static let spacing = 100

    /// Whether higher weights sort further right, decided by the members'
    /// geometry rather than by the control items' own stored pair.
    ///
    /// The controls are about to move, so their weights are not evidence. The
    /// vote counts every ordered pair, since one flipped reading would mirror
    /// the bar and confirm itself.
    ///
    /// - Parameter members: on-screen members as (horizontal centre, weight).
    /// - Returns: nil when fewer than two members carry a weight, which is
    ///   too little evidence to decide; the caller falls back to the table.
    public static func axisAscends(members: [(x: CGFloat, weight: Int)]) -> Bool? {
        guard members.count > 1 else { return nil }
        let byPosition = members.sorted { $0.x < $1.x }
        var ascending = 0
        var descending = 0
        for i in byPosition.indices {
            for j in byPosition.index(after: i) ..< byPosition.endIndex {
                if byPosition[i].weight < byPosition[j].weight {
                    ascending += 1
                } else if byPosition[i].weight > byPosition[j].weight {
                    descending += 1
                }
            }
        }
        return ascending >= descending
    }

    /// Whether weight already sorts between its neighbours, in which case the
    /// caller writes nothing. A settled bar must produce no write at all, or
    /// the pass that runs before a reveal and the one that runs after it take
    /// turns rewriting the table.
    public static func isSeated(
        _ weight: Int?,
        between before: Int?,
        and after: Int?,
        ascending: Bool
    ) -> Bool {
        guard let weight else { return false }
        let clearsBefore = before.map { ascending ? weight > $0 : weight < $0 } ?? true
        let clearsAfter = after.map { ascending ? weight < $0 : weight > $0 } ?? true
        return clearsBefore && clearsAfter
    }

    /// A free weight strictly between before and after, or just outside a
    /// lone neighbour when the control sits at one end of the order.
    ///
    /// Returns nil when the neighbours contradict the axis, are adjacent
    /// integers, have no free weight between them, or are both absent. The
    /// caller leaves the control where it is: displacing a member to make room
    /// is the one thing manual arrangement forbids.
    public static func seat(
        between before: Int?,
        and after: Int?,
        ascending: Bool,
        avoiding taken: Set<Int>
    ) -> Int? {
        switch (before, after) {
        case let (before?, after?):
            // Fixed anchors must already agree with the axis. Sorting reversed
            // bounds would propose a seat that isSeated can never accept,
            // causing the caller to rewrite the same weight on every reveal.
            guard ascending ? before < after : before > after else { return nil }
            let low = min(before, after)
            let high = max(before, after)
            guard high - low >= 2 else { return nil }
            let midpoint = low + (high - low) / 2
            return firstFree(from: midpoint, taken: taken, exclusiveBounds: (low, high))
        case let (before?, nil):
            return firstFree(
                from: before + (ascending ? spacing : -spacing),
                taken: taken,
                exclusiveBounds: nil
            )
        case let (nil, after?):
            return firstFree(
                from: after + (ascending ? -spacing : spacing),
                taken: taken,
                exclusiveBounds: nil
            )
        case (nil, nil):
            return nil
        }
    }

    /// The nearest unused weight to candidate, staying strictly inside
    /// exclusiveBounds when the seat has to fall between two anchors.
    private static func firstFree(
        from candidate: Int,
        taken: Set<Int>,
        exclusiveBounds: (low: Int, high: Int)?
    ) -> Int? {
        func admissible(_ value: Int) -> Bool {
            guard !taken.contains(value) else { return false }
            guard let exclusiveBounds else { return true }
            return value > exclusiveBounds.low && value < exclusiveBounds.high
        }
        if admissible(candidate) {
            return candidate
        }
        for step in 1 ... 64 {
            for value in [candidate + step, candidate - step] where admissible(value) {
                return value
            }
        }
        return nil
    }
}
