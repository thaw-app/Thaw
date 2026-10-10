//
//  ExtrasMenuBarProbeMemory.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// What the extras-menu-bar probe learned about each application in earlier
/// sessions, so a cold start does not pay to learn it again.
///
/// Without it the first scan of each launch probes every app over AX (3.85s
/// in #956), right while the layout restores. An app with no extras menu bar
/// last session almost certainly has none now.
///
/// This memory only reorders work and never produces an answer: a skip leaves
/// items unresolved for one scan, never attributed to the wrong owner.
nonisolated enum ExtrasMenuBarProbeMemory {
    /// The largest number of remembered applications kept.
    ///
    /// A busy system runs ~170 applications; this only bounds growth.
    static let capacity = 1024

    /// How many consecutive misses an application must have accumulated
    /// before the result is worth remembering across launches.
    ///
    /// One miss is not evidence: an app still launching or wedged reports none,
    /// and `getOrCreateExtrasMenuBar()` can't detect every such case.
    static let minimumMissesToRemember = 2

    /// The largest miss count stored.
    ///
    /// `ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses:)`
    /// saturates at its top rung.
    static let maximumRememberedMisses = 4

    /// The state a freshly created cache entry should adopt for an
    /// application the memory has an opinion about, or `nil` when it has
    /// none worth acting on.
    ///
    /// The deadline is the *first* rung, not the one the count earns: enough to
    /// skip the cold-start scan, not enough to miss an app that gained a status
    /// item. The seeded count lets a repeat miss resume the ladder where it left off.
    static func seed(forRememberedMisses misses: Int?) -> (misses: Int, initialTTL: Duration)? {
        guard let misses, misses >= minimumMissesToRemember else {
            return nil
        }
        return (
            misses: min(misses, maximumRememberedMisses),
            initialTTL: ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses: 1)
        )
    }

    /// The memory to persist, given what was already stored and what this
    /// session observed.
    ///
    /// - Parameters:
    ///   - persisted: The memory as it was last written.
    ///   - observed: Consecutive misses per bundle identifier for the
    ///     applications running now. Zero means the application has an extras
    ///     menu bar, since finding one resets the count.
    ///   - runningBundleIDs: The applications running now, used to decide
    ///     what to evict when the memory is over capacity.
    ///
    /// An observation always wins over what was stored, so an app that now has
    /// an extras menu bar loses its entry outright.
    static func merged(
        persisted: [String: Int],
        observed: [String: Int],
        runningBundleIDs: Set<String>
    ) -> [String: Int] {
        var merged = persisted

        for (bundleID, misses) in observed {
            if misses >= minimumMissesToRemember {
                merged[bundleID] = min(misses, maximumRememberedMisses)
            } else {
                merged.removeValue(forKey: bundleID)
            }
        }

        guard merged.count > capacity else {
            return merged
        }
        // Keep everything running now; evict the rest, like `MenuBarItemNameMemory`.
        return merged.filter { runningBundleIDs.contains($0.key) }
    }
}
