//
//  AXIdentityCatalog.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import AXSwift6
import Cocoa

/// Snapshots AX identity for menu bar items from a few host apps and
/// correlates it with CG window bounds by frame overlap.
///
/// A last resort when CG identity is degraded or ambiguous; it never
/// overrides a confident CG match. Snapshots are on demand, time-limited,
/// and bounded so a slow app or huge AX tree can't block the caller.
@MainActor
enum AXIdentityCatalog {
    /// AX-derived identity for a single menu-bar-hosted element.
    nonisolated struct AXItemIdentity {
        let identifier: String?
        let title: String?
        let help: String?
        let frame: CGRect
    }

    /// So a non-responsive app can't block a snapshot.
    private static let messagingTimeout: Float = 0.25

    /// Maximum depth walked below each host's extras menu bar element.
    private static let maxWalkDepth = 6

    /// Across all hosts in one snapshot.
    private static let maxElementsVisited = 512

    /// Bounds the total MainActor stall; per-call timeouts still add up.
    private static let maxSnapshotDuration = Duration.milliseconds(500)

    /// Minimum overlap, as a fraction of the smaller rect, for a confident
    /// match.
    private static nonisolated let minOverlapFraction: CGFloat = 0.5

    /// Only elements with a frame are included, since the frame is the only
    /// correlation key.
    static func snapshot(hosts: [NSRunningApplication]) -> [AXItemIdentity] {
        var results = [AXItemIdentity]()
        var visited = 0
        let deadline = ContinuousClock.now.advanced(by: maxSnapshotDuration)

        for host in hosts {
            guard visited < maxElementsVisited, ContinuousClock.now < deadline else { break }
            guard let app = AXHelpers.application(for: host) else { continue }
            try? app.setMessagingTimeout(messagingTimeout)
            guard let extrasMenuBar = AXHelpers.extrasMenuBar(for: app) else { continue }
            try? extrasMenuBar.setMessagingTimeout(messagingTimeout)

            walk(extrasMenuBar, depth: 0, visited: &visited, deadline: deadline, into: &results)
        }

        return results
    }

    private static func walk(
        _ element: UIElement,
        depth: Int,
        visited: inout Int,
        deadline: ContinuousClock.Instant,
        into results: inout [AXItemIdentity]
    ) {
        walk(
            element,
            depth: depth,
            visited: &visited,
            deadline: deadline,
            into: &results,
            identityFor: { element in
                try? element.setMessagingTimeout(messagingTimeout)

                guard let frame = AXHelpers.frame(for: element) else {
                    return nil
                }
                return AXItemIdentity(
                    identifier: AXHelpers.identifier(for: element),
                    title: AXHelpers.title(for: element),
                    help: AXHelpers.help(for: element),
                    frame: frame
                )
            },
            childrenFor: { AXHelpers.children(for: $0) }
        )
    }

    /// Generic so the bounds can be tested without live AX handles.
    static func walk<Node>(
        _ element: Node,
        depth: Int,
        visited: inout Int,
        deadline: ContinuousClock.Instant,
        into results: inout [AXItemIdentity],
        identityFor: (Node) -> AXItemIdentity?,
        childrenFor: (Node) -> [Node]
    ) {
        guard depth <= maxWalkDepth, visited < maxElementsVisited,
              ContinuousClock.now < deadline
        else { return }
        visited += 1

        if let identity = identityFor(element) {
            results.append(identity)
        }

        guard depth < maxWalkDepth else { return }
        for child in childrenFor(element) {
            guard visited < maxElementsVisited, ContinuousClock.now < deadline else { return }
            walk(
                child,
                depth: depth + 1,
                visited: &visited,
                deadline: deadline,
                into: &results,
                identityFor: identityFor,
                childrenFor: childrenFor
            )
        }
    }

    /// Returns the best identity match for `windowBounds` among `snapshot`,
    /// or `nil` when no candidate correlates confidently.
    ///
    /// Picks the largest intersection above `minOverlapFraction`. A tie for
    /// first returns `nil`.
    static nonisolated func identity(
        for windowBounds: CGRect,
        in snapshot: [AXItemIdentity]
    ) -> AXItemIdentity? {
        let targetArea = windowBounds.width * windowBounds.height

        let scored = snapshot.compactMap { candidate -> (identity: AXItemIdentity, area: CGFloat)? in
            let intersection = candidate.frame.intersection(windowBounds)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }

            let intersectionArea = intersection.width * intersection.height
            let candidateArea = candidate.frame.width * candidate.frame.height
            let smallerArea = min(candidateArea, targetArea)
            guard smallerArea > 0, intersectionArea > smallerArea * minOverlapFraction else { return nil }

            return (candidate, intersectionArea)
        }

        // Compare the top two directly; a running tie flag can latch after
        // the tie is beaten.
        let top = scored.max(count: 2, sortedBy: { $0.area < $1.area })
        guard let best = top.last else { return nil }
        guard top.count < 2 || top[0].area != best.area else { return nil }
        return best.identity
    }
}
