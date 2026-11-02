//
//  MenuBarAgentIdentityReconciler.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import os

/// Restores stable identities to MenuBarAgent extras that a transition walk
/// saw unnamed.
///
/// Mid-reveal, MenuBarAgent republishes its extras with no identifier yet, so
/// the walk mints positional ids (Item-0, …) that the position store's title
/// matching resolves to stale rows' keys.
///
/// An unnamed extra takes the tag of the previous walk's identified extra at
/// the same slot and keeps its fresh frame, window and on-screen state. The
/// next walk that reads identifiers overwrites any wrong carry-forward.
public enum MenuBarAgentIdentityReconciler {
    /// How far apart two slots may sit and still count as the same seat.
    /// Covers a mid-transition reflow; small against the narrowest real extra.
    static let slotTolerance: CGFloat = 8

    /// The outcome of one reconciliation.
    public struct Result: Equatable, Sendable {
        /// The items to publish: fresh geometry, restored identities.
        public let items: [MenuBarItem]
        /// How many unnamed items adopted a previous identity.
        public let restoredCount: Int
    }

    /// Carries previous identities forward onto unnamed fresh items.
    ///
    /// - Parameters:
    ///   - fresh: The walk just completed.
    ///   - previous: The last walk whose MenuBarAgent extras were identified.
    public static func reconcile(fresh: [MenuBarItem], previous: [MenuBarItem]) -> Result {
        // Only extras the host identifies can degrade to a positional name,
        // so only they have a previous identity worth carrying forward.
        var candidates = previous
            .filter { $0.tag.namespace == .menuBarAgent }
            .filter { !$0.tag.isControlCenterGenericItem }
            .filter { !$0.isControlItem && !$0.isNativeOverflowControl }
        guard !candidates.isEmpty else {
            return Result(items: fresh, restoredCount: 0)
        }

        var restoredCount = 0
        var items = fresh
        for index in items.indices where isUnnamedHostExtra(items[index].tag) {
            let midX = items[index].bounds.midX
            let best = candidates
                .enumerated()
                .min(by: { lhs, rhs in
                    let lhsDistance = abs(lhs.element.bounds.midX - midX)
                    let rhsDistance = abs(rhs.element.bounds.midX - midX)
                    return lhsDistance == rhsDistance
                        ? lhs.element.bounds.midX < rhs.element.bounds.midX
                        : lhsDistance < rhsDistance
                })
            guard let match = best, abs(match.element.bounds.midX - midX) <= slotTolerance else {
                continue
            }
            items[index] = MenuBarItem(
                tag: match.element.tag,
                windowID: items[index].windowID,
                ownerPID: items[index].ownerPID,
                sourcePID: items[index].sourcePID,
                bounds: items[index].bounds,
                title: items[index].title,
                isOnScreen: items[index].isOnScreen
            )
            candidates.remove(at: match.offset)
            restoredCount += 1
        }
        return Result(items: items, restoredCount: restoredCount)
    }

    /// Whether a tag is the positional identity a hosting-process child mints
    /// when the transition deprived it of every naming attribute.
    private static func isUnnamedHostExtra(_ tag: MenuBarItemTag) -> Bool {
        tag.isUnnamedMenuBarAgentExtra
    }

    // MARK: Stateful front for walk call sites

    /// The last walk whose MenuBarAgent extras were identified. Walk call
    /// sites with no memory of their previous answer reconcile against this.
    private static let lastIdentified = OSAllocatedUnfairLock<[MenuBarItem]>(
        initialState: []
    )

    private static let diagLog = DiagLog(category: "MenuBarAgentIdentityReconciler")

    /// Reconciles fresh against the last identified walk and remembers it.
    ///
    /// Degraded and empty walks leave the snapshot standing, so a transition
    /// cannot erase the memory the next degraded walk needs.
    public static func reconciling(_ fresh: [MenuBarItem]) -> Result {
        let previous = lastIdentified.withLock { $0 }
        let result = reconcile(fresh: fresh, previous: previous)
        let carriesIdentity = result.items.contains { item in
            item.tag.namespace == .menuBarAgent && !item.tag.isControlCenterGenericItem
        }
        if carriesIdentity {
            lastIdentified.withLock { $0 = result.items }
        }
        if result.restoredCount > 0 {
            diagLog.warning(
                "\(result.restoredCount) MenuBarAgent extra(s) arrived unnamed; identity restored from the previous walk"
            )
        }
        return result
    }

    /// Forgets the snapshot. Tests only.
    static func resetState() {
        lastIdentified.withLock { $0 = [] }
    }
}
