//
//  MenuBarItemImageCache+PrewarmExclusion.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@MainActor
extension MenuBarItemImageCache {
    /// Whether a recapture pass should skip while Capture Hidden Items runs. Its reveals
    /// count as unhidden, so a pass would crop them while they slide in.
    func standsDownForConcealedPrewarm(_ pass: String) -> Bool {
        guard isConcealedPrewarmRunning else { return false }
        MenuBarItemImageCache.diagLog.debug("\(pass): hidden items are being captured; skipping this pass")
        return true
    }

    /// Opens the tally once a prewarm holds the slot, and makes any pass admitted before it go stale.
    func markConcealedPrewarmStarted(tally: RequestedCaptureTally?) {
        Self.requestedCaptureTally = tally
        appState?.itemManager.layoutPublication.invalidate()
    }
}
