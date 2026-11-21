//
//  MenuBarItemManager+AppLaunch.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension MenuBarItemManager {
    /// Logs a launch and settles the bar when it is a relaunch of an app Thaw tracks an item for.
    func noteAppLaunched(bundleID: String?) {
        Self.diagLog.debug("App launched\(bundleID.map { " (\($0))" } ?? "")")
        if let settle = Self.launchSettle(bundleID: bundleID, knownIdentifiers: knownItemIdentifiers) {
            barSettling.note(settle)
        }
    }

    /// The settle a launch starts. A tracked app's item is about to re-register, and the move pass waits on
    /// barSettling.settled() until it re-pairs, or a bulk apply on the moving bar sweeps hidden items into Visible.
    static nonisolated func launchSettle(bundleID: String?, knownIdentifiers: Set<String>) -> BarSettling.Disturbance? {
        guard let bundleID, tracksMenuBarItem(bundleID: bundleID, in: knownIdentifiers) else { return nil }
        return .appLaunched(bundleID: bundleID)
    }
}
