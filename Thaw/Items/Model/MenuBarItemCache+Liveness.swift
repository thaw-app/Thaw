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
                if item.ownerPID > 0 {
                    // A relaunch has a new PID; its old snapshot must not stand
                    // in for the new process's still-unobserved status item.
                    return processIDs.contains(item.ownerPID)
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

    /// Live process table variant of
    /// retainingRunningOwners(processIDs:bundleIdentifiers:).
    @MainActor
    func retainingRunningOwners() -> Self {
        let applications = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        return retainingRunningOwners(
            processIDs: Set(applications.map(\.processIdentifier)),
            bundleIdentifiers: Set(applications.compactMap(\.bundleIdentifier))
        )
    }
}
