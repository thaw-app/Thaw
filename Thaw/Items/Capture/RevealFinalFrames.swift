//
//  RevealFinalFrames.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension MenuBarItemImageCache {
    /// Settles a revealed batch where it ends up. Under Native hiding the reveal rebuilds the
    /// bar, so an item can reach its slot after its first read; settling and cropping at that
    /// stale frame watches pixels that never change and cuts the wrong ones. Reads the items
    /// that appeared again after the settle, and settles once more at the new frames when any moved.
    @MainActor
    func settleAtFinalFrames(
        _ firstRead: [(requested: MenuBarItem, live: MenuBarItem)],
        using sources: RevealCaptureSources
    ) async -> [(requested: MenuBarItem, live: MenuBarItem)] {
        await sources.renderSettle(firstRead.map(\.live))
        guard !Task.isCancelled else { return firstRead }
        // Only what appeared: an item that never drew would cost another full wait.
        let reread = await sources.settledItems(firstRead.map(\.requested))
        guard Self.anyRevealMoved(from: firstRead, to: reread) else { return firstRead }
        MenuBarItemImageCache.diagLog.debug("grouped reveal capture: items moved after their first read; settling again where they ended up")
        await sources.renderSettle(reread.map(\.live))
        return reread
    }

    /// Whether a second read put any item of the first somewhere else.
    static nonisolated func anyRevealMoved(
        from first: [(requested: MenuBarItem, live: MenuBarItem)],
        to second: [(requested: MenuBarItem, live: MenuBarItem)]
    ) -> Bool {
        let earlier = Dictionary(first.map { ($0.requested.uniqueIdentifier, $0.live.bounds) }, uniquingKeysWith: { first, _ in first })
        return second.contains { pair in
            earlier[pair.requested.uniqueIdentifier].map { !hasStableCaptureBounds(before: $0, after: pair.live.bounds) } ?? false
        }
    }
}
