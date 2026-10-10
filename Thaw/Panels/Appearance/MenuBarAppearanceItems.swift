//
//  MenuBarAppearanceItems.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

@MainActor
enum MenuBarAppearanceItems {
    struct Snapshot {
        let items: [MenuBarItem]
        let readAt: ContinuousClock.Instant
    }

    static func geometry(
        from snapshot: Snapshot,
        on screenFrame: CGRect,
        displayBounds: [CGRect],
        context: MenuBarSplitPillGeometry.TrailingPillContext
    ) -> MenuBarGeometryRefresh.Snapshot {
        let items = snapshot.items.filter {
            MenuBarItemGeometry.barScreen(holding: $0.bounds, among: displayBounds) != nil
        }
        func mirroredFrame(_ frame: CGRect) -> CGRect {
            MirroredBarGeometry.frame(frame, on: screenFrame, displayBounds: displayBounds)
        }
        // AX reports one bar's frames even when macOS draws its status items on every display.
        // Apply section/parking policy before translating drawing bounds, not managed item identities.
        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            screenFrame: screenFrame,
            context: context,
            mapBounds: mirroredFrame
        )
        let sourceScreens = Set(items.compactMap {
            MenuBarItemGeometry.barScreen(holding: $0.bounds, among: displayBounds)
        })
        let isRevealingHidden = context.revealedSection == .hidden
            || context.revealedSection == .alwaysHidden
        return MenuBarGeometryRefresh.Snapshot(
            itemBounds: bounds,
            chevronFrame: isRevealingHidden
                ? .zero
                : (items.first(where: { $0.tag.matchesVisibleControlItem }).map { mirroredFrame($0.bounds) } ?? .zero),
            sourceScreenFrame: sourceScreens.count == 1 ? sourceScreens.first : nil,
            readAt: snapshot.readAt
        )
    }

    static func read(
        knownItems: [MenuBarItem],
        onScreenSnapshot: OnScreenItemSnapshot?,
        notBefore minimumReadTime: ContinuousClock.Instant?,
        readOwners: (Set<pid_t>) async -> [MenuBarItem]?,
        discover: () async -> [MenuBarItem]
    ) async -> Snapshot? {
        let readAt = ContinuousClock.now
        let recentItems = onScreenSnapshot?.items ?? []
        let recentOwners = Set(recentItems.map { $0.sourcePID ?? $0.ownerPID })
        let owners = recentOwners.union(knownItems.map { $0.sourcePID ?? $0.ownerPID })
        // Recent truncated or concealed snapshots can omit owners whose icons are about to appear.
        if owners.isSubset(of: recentOwners),
           let recentAt = onScreenSnapshot?.timestamp,
           recentAt.duration(to: readAt) < .milliseconds(200),
           minimumReadTime.map({ recentAt >= $0 }) ?? true
        {
            return Snapshot(items: recentItems, readAt: recentAt)
        }
        if !owners.isEmpty {
            guard let fresh = await readOwners(owners) else { return nil }
            return Snapshot(items: fresh, readAt: readAt)
        }
        return await Snapshot(items: discover(), readAt: readAt)
    }
}
