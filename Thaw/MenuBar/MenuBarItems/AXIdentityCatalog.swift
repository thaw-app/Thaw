//
//  AXIdentityCatalog.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import AXSwift6
import Cocoa

/// Snapshots AX-derived identity (identifier, title, help, frame) for
/// menu-bar-hosted items from a small set of host apps, and correlates
/// those identities against CG window bounds by frame overlap.
///
/// This is a secondary identity channel used as a tie-breaker/last-resort
/// when CG-window-level identity (title/tag) is degraded or ambiguous — see
/// plan 014. It never overrides a confident CG-side match; primary tag/title
/// matching stays authoritative.
///
/// Snapshots are taken on demand only (no timers/observers), every AX
/// access is guarded by a short messaging timeout so a non-responsive app
/// can't block a caller, and the child walk is bounded so a pathological AX
/// tree can't make a snapshot expensive.
@MainActor
enum AXIdentityCatalog {
    /// AX-derived identity for a single menu-bar-hosted element.
    nonisolated struct AXItemIdentity {
        let identifier: String?
        let title: String?
        let help: String?
        let frame: CGRect
    }

    /// Messaging timeout applied to AX handles created here, so a
    /// non-responsive app can't block a snapshot indefinitely.
    private static let messagingTimeout: Float = 0.25

    /// Maximum depth walked below each host's extras menu bar element.
    private static let maxWalkDepth = 6

    /// Maximum number of elements visited across an entire snapshot, across
    /// all hosts. Bounds worst-case snapshot cost regardless of AX tree
    /// shape.
    private static let maxElementsVisited = 512

    /// Maximum wall-clock time spent across an entire snapshot, across all
    /// hosts. Even with per-call messaging timeouts, hundreds of slow AX
    /// calls can add up; this bounds the aggregate MainActor stall.
    private static let maxSnapshotDuration = Duration.milliseconds(500)

    /// Minimum fraction of the smaller rect's area that must be covered by
    /// the intersection for a correlation to be considered confident.
    /// Correlations below this threshold return `nil` rather than guessing.
    private static nonisolated let minOverlapFraction: CGFloat = 0.5

    /// Takes a snapshot of menu-bar-item AX identities from the given host
    /// applications (e.g. Control Center, SystemUIServer, or Thaw itself).
    ///
    /// Only elements that publish a frame are included, since frame is the
    /// sole correlation key against CG window bounds.
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

    /// Depth-limited, element-capped, time-budgeted walk collecting
    /// identities from `element` and its children.
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

    /// Walks a bounded identity tree. The generic traversal keeps the safety
    /// rules independent of live Accessibility handles so they can be verified
    /// with deterministic trees while the adapter above remains responsible
    /// for AX reads and messaging timeouts.
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
    /// Correlation is the highest-intersection-area candidate, requiring the
    /// intersection area to exceed `minOverlapFraction` of the smaller of
    /// the two rects' areas. A tie between the top two candidates is treated
    /// as ambiguous and returns `nil` rather than guessing.
    static nonisolated func identity(
        for windowBounds: CGRect,
        in snapshot: [AXItemIdentity]
    ) -> AXItemIdentity? {
        let targetArea = windowBounds.width * windowBounds.height

        // Candidates whose overlap clears the confidence threshold, paired
        // with the area that ranks them.
        let scored = snapshot.compactMap { candidate -> (identity: AXItemIdentity, area: CGFloat)? in
            let intersection = candidate.frame.intersection(windowBounds)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }

            let intersectionArea = intersection.width * intersection.height
            let candidateArea = candidate.frame.width * candidate.frame.height
            let smallerArea = min(candidateArea, targetArea)
            guard smallerArea > 0, intersectionArea > smallerArea * minOverlapFraction else { return nil }

            return (candidate, intersectionArea)
        }

        // Ranking the top two is the whole decision: the larger one wins,
        // and a tie between them means the frame cannot pick a side, which
        // is a nil rather than a guess. Tracking that with a running best
        // and a tie flag instead invites the flag to latch after a tie is
        // later beaten -- a bug this shape cannot express.
        let top = scored.max(count: 2, sortedBy: { $0.area < $1.area })
        guard let best = top.last else { return nil }
        guard top.count < 2 || top[0].area != best.area else { return nil }
        return best.identity
    }
}
