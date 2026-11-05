//
//  MenuBarItemCache+Liveness.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel

extension MenuBarItemCache {
    /// Removes departed owners after rebucketing has restored concealed
    /// snapshots, the resurrection path purgeItemsOwnedBy(_:) cannot
    /// see: the purge runs when the owner exits, while rebucketing
    /// resurrects the snapshot on every later cache pass.
    func retainingRunningOwners(
        processIDs: Set<pid_t>,
        bundleIdentifiers: Set<String>
    ) -> Self {
        var cache = self
        for section in MenuBarSectionName.allCases {
            cache[section] = cache[section].filter { item in
                let livenessPID = item.sourcePID ?? item.ownerPID
                if livenessPID > 0 {
                    // A relaunch has a new PID; its old snapshot must not stand
                    // in for the new process's still-unobserved status item.
                    return processIDs.contains(livenessPID)
                }
                // Persisted conceal snapshots deliberately have no PID. Keep
                // those only while their publishing bundle is actually running.
                guard case let .string(bundleIdentifier) = item.tag.namespace else {
                    return false
                }
                return bundleIdentifiers.contains(bundleIdentifier)
            }
        }
        return cache
    }

    /// Fresh items plus the cached ones a partial AX walk missed whose apps still run. macOS 27.2
    /// can leave out Thaw's own AXExtrasMenuBar while every other app answers.
    static func mergingLiveCachedItems(
        snapshotItems: [MenuBarItem],
        previousCachedItems: [MenuBarItem],
        processIDs: Set<pid_t>,
        bundleIdentifiers: Set<String>
    ) -> [MenuBarItem] {
        var previousCache = MenuBarItemCache(displayID: nil)
        previousCache[.visible] = previousCachedItems
        let liveCachedItems = previousCache.retainingRunningOwners(
            processIDs: processIDs,
            bundleIdentifiers: bundleIdentifiers
        ).managedItems
        return MenuBarItemCache.merging(snapshotItems, withCachedItems: liveCachedItems)
    }
}
