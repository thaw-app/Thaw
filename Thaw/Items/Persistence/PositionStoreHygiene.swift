//
//  PositionStoreHygiene.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import PlatformRuntimeKit

/// MenuBarAgent never removes preferred-position keys; stale weights interfere with interpolation.
/// Prune only uninstalled owners, not stopped apps, to preserve user-arranged positions.
@MainActor
enum PositionStoreHygiene {
    private static let diagLog = DiagLog(category: "PositionStoreHygiene")

    /// Keys seen dead on a previous pass, awaiting a second opinion.
    private static let candidatesKey = "MenuBarItemManager.positionStoreHygieneCandidates"

    /// The live store requires macOS 27, but the pruning rules can be tested independently.
    static func pruneCurrentStore(permit: borrowing StoreWritePermit) {
        let store = MenuBarPositionStoreProvider.current
        prune(positions: store.readPositions()) { doomed in
            // Re-read before replacing the dictionary to preserve weights changed by the host in another process.
            var positions = store.readPositions()
            // An empty re-read may be a read failure; writing it back could erase live positions.
            guard !positions.isEmpty else {
                diagLog.error("hygiene: skipped write, re-read came back empty")
                return
            }
            for key in doomed {
                positions.removeValue(forKey: key)
            }
            store.writePositions(positions, permit: permit)
            PositionStoreItemSource.invalidateStoreSnapshot()
        }
    }

    /// Requires two launches to confirm absence because updates, unmounted volumes and Launch Services delays can hide installed apps.
    /// Calls remove only for a nonempty set and returns those keys sorted.
    @discardableResult
    static func prune(
        positions: [String: Int],
        defaults: UserDefaults = .standard,
        remove: (Set<String>) -> Void
    ) -> [String] {
        let previousCandidates = Set(defaults.stringArray(forKey: candidatesKey) ?? [])
        let liveOwners = currentOwnerNames()
        let candidates = Set(positions.keys.filter { isDead($0, liveOwners: liveOwners) })

        let doomed = candidates.intersection(previousCandidates)
        defaults.set(Array(candidates.subtracting(doomed)).sorted(), forKey: candidatesKey)

        guard !doomed.isEmpty else {
            if !candidates.isEmpty {
                diagLog.info("hygiene: \(candidates.count) key(s) newly unowned; deferring to next launch")
            }
            return []
        }

        remove(doomed)

        let removed = doomed.sorted()
        diagLog.info("hygiene: pruned \(removed.count) of \(positions.count) key(s): \(removed)")
        return removed
    }

    /// Status keys may use bundle IDs or display/process names, such as iStatMenusMenubar.
    /// Collect all forms so bundle lookup failures do not mark running owners as dead.
    private static func currentOwnerNames() -> Set<String> {
        var names = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let bundleID = app.bundleIdentifier {
                names.insert(bundleID)
            }
            if let localized = app.localizedName {
                names.insert(localized)
            }
            if let executable = app.executableURL?.lastPathComponent {
                names.insert(executable)
            }
        }
        return names
    }

    private static func isDead(_ key: String, liveOwners: Set<String>) -> Bool {
        // Never prune module keys: a disabled Apple module's weight is indistinguishable from an idle one's.
        guard let parsed = MenuBarPositionStoreProvider.current.parseStatusKey(key) else {
            return false
        }
        let owner = parsed.owner

        // Apple's own items come and go with OS features rather than with
        // anything installed, and Thaw's keys are rewritten by Thaw itself.
        guard !owner.hasPrefix("com.apple."),
              !owner.hasPrefix("com.stonerl.Thaw")
        else {
            return false
        }

        if liveOwners.contains(owner) {
            return false
        }

        // Dotless owners are display names; bundle lookup always fails for them and cannot prove absence.
        guard owner.contains(".") else {
            return false
        }

        // Preserve installed apps' positions for their next launch.
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: owner) != nil {
            return false
        }

        return true
    }
}
