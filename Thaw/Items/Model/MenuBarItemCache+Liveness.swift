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
    ///
    /// A hidden item whose process exited stays, without that process, while
    /// its app runs again. macOS hides the relaunched app's item before any
    /// walk can read it, so the snapshot is the only record of it.
    func retainingRunningOwners(
        processIDs: Set<pid_t>,
        bundleIdentifiers: Set<String>
    ) -> Self {
        // A relaunched app's hidden items are all unread, so none of them has a
        // running process. An app that has one is another copy still running.
        let appsWithRunningItems = Set(MenuBarSectionName.allCases.flatMap { self[$0] }.compactMap { item -> String? in
            let pid = item.sourcePID ?? item.ownerPID
            return pid > 0 && processIDs.contains(pid) ? item.tag.namespace.bundleIdentifier : nil
        })
        var cache = self
        for section in MenuBarSectionName.allCases {
            cache[section] = cache[section].compactMap { item in
                let livenessPID = item.sourcePID ?? item.ownerPID
                if livenessPID > 0, processIDs.contains(livenessPID) {
                    return item
                }
                guard let bundleIdentifier = item.tag.namespace.bundleIdentifier,
                      bundleIdentifiers.contains(bundleIdentifier)
                else {
                    return nil
                }
                guard livenessPID > 0 else {
                    return item
                }
                // A relaunched app draws its visible items, so the next walk
                // reads the new process's own item in place of the old one.
                guard section != .visible, !appsWithRunningItems.contains(bundleIdentifier) else {
                    return nil
                }
                // Persisted conceal snapshots have no PID. Dropping the exited
                // process's PID makes this one alike: lookups resolve the
                // running process, and liveness follows the bundle.
                return item.withoutOwnerProcess
            }
        }
        return cache
    }

    /// The processes retainingRunningOwners(processIDs:bundleIdentifiers:) checks by PID.
    var livenessPIDs: Set<pid_t> {
        var pids = Set<pid_t>()
        for section in MenuBarSectionName.allCases {
            for item in self[section] {
                let pid = item.sourcePID ?? item.ownerPID
                if pid > 0 {
                    pids.insert(pid)
                }
            }
        }
        return pids
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

private extension MenuBarItem {
    /// The item as a persisted conceal snapshot carries it, owned by no process.
    var withoutOwnerProcess: MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: windowID,
            ownerPID: 0,
            sourcePID: nil,
            bounds: bounds,
            title: title,
            isOnScreen: isOnScreen
        )
    }
}
