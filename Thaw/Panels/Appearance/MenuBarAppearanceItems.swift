//
//  MenuBarAppearanceItems.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import ThawAXCore

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

    /// The last owner read and the bar it described. Shared, since every display's overlay asks about
    /// the same bar.
    @MainActor
    final class Memo {
        static let shared = Memo()
        fileprivate var last: (bar: [MenuBarAgentWindow.Entry], owners: Set<pid_t>, items: [MenuBarItem])?
    }

    /// - Parameters:
    ///   - drawnBar: The bar as MenuBarAgent draws it now, or nil when that cannot be told. One read
    ///     of one process, where asking the owners is one read per app.
    ///   - memo: Where the last owner read is kept. With a bar that has not moved since, and the same
    ///     owners to ask, that read is still true and the owners are not asked again.
    static func read(
        knownItems: [MenuBarItem],
        onScreenSnapshot: OnScreenItemSnapshot?,
        notBefore minimumReadTime: ContinuousClock.Instant?,
        drawnBar: () async -> [MenuBarAgentWindow.Entry]? = { nil },
        memo: Memo? = nil,
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
            // Read before the owners are asked: a bar that moves in between leaves the memo describing
            // the older bar, so the next read sees a difference and asks again.
            let bar = await drawnBar()
            if let bar, let last = memo?.last, last.bar == bar, last.owners == owners {
                return Snapshot(items: last.items, readAt: readAt)
            }
            guard let fresh = await readOwners(owners) else { return nil }
            memo?.last = bar.map { ($0, owners, fresh) }
            return Snapshot(items: fresh, readAt: readAt)
        }
        return await Snapshot(items: discover(), readAt: readAt)
    }
}
