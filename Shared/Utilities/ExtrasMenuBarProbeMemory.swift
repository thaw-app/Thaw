//
//  ExtrasMenuBarProbeMemory.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// What the extras-menu-bar probe learned about each application in earlier
/// sessions, so a cold start does not pay to learn it again.
///
/// `ExtrasMenuBarNegativeCachePolicy` keeps a full scan off the ~155 of ~170
/// running applications that have no extras menu bar, but it builds that
/// knowledge from nothing every launch: the first scan after start probes
/// every application over the Accessibility API, and an AX read is serviced
/// by the *target* process on its main thread. That scan measured 3.85s in
/// the log attached to #956, landing squarely in the window where the app is
/// restoring a layout and the user is trying to use their machine.
///
/// An application that had no extras menu bar last session almost certainly
/// has none now, and remembering that is the difference between probing the
/// system and probing the handful of hosts that matter.
///
/// This memory only ever reorders work; it can never produce an answer.
/// Skipping an application leaves items unresolved for one scan, which the
/// layout gates already wait for and `MenuBarItemNameMemory` already papers
/// over for display — it cannot attribute an item to the wrong owner, which
/// is why the memory is trusted here and deliberately not trusted for
/// identity.
nonisolated enum ExtrasMenuBarProbeMemory {
    /// The largest number of remembered applications kept.
    ///
    /// A busy system runs ~170 applications; the rest of the budget absorbs
    /// years of installing and removing them. An entry for an application
    /// that is never launched again is never read, so this exists only to
    /// bound growth.
    static let capacity = 1024

    /// How many consecutive misses an application must have accumulated
    /// before the result is worth remembering across launches.
    ///
    /// One miss is not evidence. An application probed while it was still
    /// launching, or while it was wedged, reports no extras menu bar for
    /// reasons that have nothing to do with whether it has one — and
    /// `getOrCreateExtrasMenuBar()` only refuses to count the cases it can
    /// detect. Two consecutive misses within a session is the cheapest
    /// filter that excludes the transient one.
    static let minimumMissesToRemember = 2

    /// The largest miss count stored.
    ///
    /// `ExtrasMenuBarNegativeCachePolicy.ttl(afterConsecutiveMisses:)`
    /// saturates at its top rung, so counting past it records nothing the
    /// ladder can act on.
    static let maximumRememberedMisses = 4

    /// The state a freshly created cache entry should adopt for an
    /// application the memory has an opinion about, or `nil` when it has
    /// none worth acting on.
    ///
    /// The deadline is deliberately the *first* rung rather than the one the
    /// miss count earns. Memory is good enough to say "probably nothing
    /// here", which is exactly the claim needed to stay out of the cold-start
    /// scan — the most expensive scan there is, and the one running while
    /// half the system is still launching. It is not good enough to buy five
    /// minutes of silence: an application that gained a status item since
    /// last session would go unnoticed for that whole window. One confirming
    /// probe a few seconds later settles it, and costs a single AX round trip
    /// at a moment when nothing else is competing for the main thread.
    ///
    /// The seeded count is what makes the confirmation cheap: an application
    /// that misses again resumes the ladder where it left off instead of
    /// climbing 5s → 30s → 120s → 300s from the bottom a second time.
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
    /// An observation always wins over what was stored, in both directions:
    /// an application that has since published an extras menu bar loses its
    /// entry outright rather than decaying out of one, because a stale entry
    /// here costs that application's items a scan on every future launch.
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
        // Everything running now is worth keeping and the overflow is
        // necessarily made up of applications that are not, which mirrors how
        // `MenuBarItemNameMemory` sheds its own overflow.
        return merged.filter { runningBundleIDs.contains($0.key) }
    }
}
