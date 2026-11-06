//
//  ReducedModeInventory+Live.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// The read of the running apps and the position table. The rule that picks from them is in ReducedModeInventory.swift.
extension ReducedModeInventory {
    @MainActor
    static func current() -> [ReducedModeApp] {
        let store = MenuBarPositionStoreProvider.current
        let keys = store.positionsDomainIsAccessible() ? Array(store.currentPositions().keys) : nil
        let own = Bundle.main.bundleIdentifier
        return candidates(
            running: NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map {
                Running(
                    bundleID: $0.bundleIdentifier,
                    name: $0.localizedName,
                    isBackgroundOnly: $0.activationPolicy == .prohibited
                )
            },
            // An empty table means nothing was learned, not that nothing has an item.
            tableKeys: keys.flatMap { $0.isEmpty ? nil : $0 },
            isOwn: { $0 == own }
        )
    }
}
