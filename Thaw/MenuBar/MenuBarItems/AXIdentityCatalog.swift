//
//  AXIdentityCatalog.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

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
    struct AXItemIdentity {
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

    /// Minimum fraction of the smaller rect's area that must be covered by
    /// the intersection for a correlation to be considered confident.
    /// Correlations below this threshold return `nil` rather than guessing.
    private nonisolated static let minOverlapFraction: CGFloat = 0.5

    /// Takes a snapshot of menu-bar-item AX identities from the given host
    /// applications (e.g. Control Center, SystemUIServer, or Thaw itself).
    ///
    /// Only elements that publish a frame are included, since frame is the
    /// sole correlation key against CG window bounds.
    static func snapshot(hosts: [NSRunningApplication]) -> [AXItemIdentity] {
        var results = [AXItemIdentity]()
        var visited = 0

        for host in hosts {
            guard visited < maxElementsVisited else { break }
            guard let app = AXHelpers.application(for: host) else { continue }
            try? app.setMessagingTimeout(messagingTimeout)
            guard let extrasMenuBar = AXHelpers.extrasMenuBar(for: app) else { continue }
            try? extrasMenuBar.setMessagingTimeout(messagingTimeout)

            walk(extrasMenuBar, depth: 0, visited: &visited, into: &results)
        }

        return results
    }

    /// Depth-limited, element-capped walk collecting identities from `element`
    /// and its children.
    private static func walk(
        _ element: UIElement,
        depth: Int,
        visited: inout Int,
        into results: inout [AXItemIdentity]
    ) {
        guard depth <= maxWalkDepth, visited < maxElementsVisited else { return }
        visited += 1

        try? element.setMessagingTimeout(messagingTimeout)

        if let frame = AXHelpers.frame(for: element) {
            results.append(
                AXItemIdentity(
                    identifier: AXHelpers.identifier(for: element),
                    title: AXHelpers.title(for: element),
                    help: AXHelpers.help(for: element),
                    frame: frame
                )
            )
        }

        guard depth < maxWalkDepth else { return }
        for child in AXHelpers.children(for: element) {
            guard visited < maxElementsVisited else { return }
            walk(child, depth: depth + 1, visited: &visited, into: &results)
        }
    }

    /// Returns the best identity match for `windowBounds` among `snapshot`,
    /// or `nil` when no candidate correlates confidently.
    ///
    /// Correlation is the highest-intersection-area candidate, requiring the
    /// intersection area to exceed `minOverlapFraction` of the smaller of
    /// the two rects' areas. A tie between the top two candidates is treated
    /// as ambiguous and returns `nil` rather than guessing.
    nonisolated static func identity(
        for windowBounds: CGRect,
        in snapshot: [AXItemIdentity]
    ) -> AXItemIdentity? {
        var best: (identity: AXItemIdentity, area: CGFloat)?
        var bestIsTied = false

        for candidate in snapshot {
            let intersection = candidate.frame.intersection(windowBounds)
            guard !intersection.isNull, !intersection.isEmpty else { continue }

            let intersectionArea = intersection.width * intersection.height
            let candidateArea = candidate.frame.width * candidate.frame.height
            let targetArea = windowBounds.width * windowBounds.height
            let smallerArea = min(candidateArea, targetArea)
            guard smallerArea > 0, intersectionArea > smallerArea * minOverlapFraction else { continue }

            if let current = best {
                if intersectionArea > current.area {
                    best = (candidate, intersectionArea)
                    bestIsTied = false
                } else if intersectionArea == current.area {
                    bestIsTied = true
                }
            } else {
                best = (candidate, intersectionArea)
                bestIsTied = false
            }
        }

        guard let best, !bestIsTied else { return nil }
        return best.identity
    }
}
