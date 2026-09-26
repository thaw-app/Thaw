//
//  StaleIdentifierLedger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - StaleIdentifierLedger

/// Tracks saved identifiers that no longer match anything on the bar.
///
/// Saved orders keep closed apps on purpose, so they return to their slot.
/// But an app that changes its bundle identifier leaves an entry nothing can
/// match, and every such ghost ahead of a live entry inflates the index
/// ``LayoutSolver/savedPositionByBaseID(for:in:)`` returns, pushing
/// returning apps further right.
///
/// A closed app comes back; a retired identity doesn't. This counts
/// consecutive unmatched applies. Retirement deletes nothing and one live
/// match undoes it, since an item Thaw can't attribute yet (Little Snitch
/// before its marker window) looks the same as a rename.
@MainActor
final class StaleIdentifierLedger {
    /// How many consecutive unmatched applies retire an identifier. Applies
    /// aren't timed, so this is large enough that quitting an app for an
    /// afternoon never reaches it.
    static let retirementThreshold = 10

    /// The largest share of a planned order that may go unmatched before the
    /// sample is discarded. Partly degraded PID resolution can mislabel a
    /// third of the bar as absent, which would retire real items in batches.
    static let maxUnmatchedFraction = 0.25

    private static nonisolated let diagLog = DiagLog(category: "StaleIdentifierLedger")

    /// The build string persisted counts are valid for; a change drops them,
    /// since a new build may resolve identities the old one couldn't.
    private static nonisolated var currentBuildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    /// Consecutive unmatched applies, keyed by canonical identifier.
    private var missCounts: [String: Int]

    init() {
        let storedBuild = Defaults.string(forKey: .staleIdentifierMissCountsBuild)
        let versionChanged = storedBuild != Self.currentBuildVersion

        missCounts = versionChanged
            ? [:]
            : Defaults.dictionary(forKey: .staleIdentifierMissCounts) as? [String: Int] ?? [:]

        if versionChanged {
            Self.diagLog.info(
                "Build changed (\(storedBuild ?? "none") -> \(Self.currentBuildVersion)); dropping stale-identifier counts"
            )
            persist()
        }
    }

    // MARK: Querying

    /// The identifiers that have gone unmatched often enough to stop
    /// planning against.
    var retiredIdentifiers: Set<String> {
        Set(missCounts.filter { $0.value >= Self.retirementThreshold }.keys)
    }

    /// Whether the given identifier should be left out of a plan.
    ///
    /// Canonicalizes here so callers can't check a different key than
    /// ``recordApply(planned:matched:)`` recorded under.
    func isRetired(_ identifier: String) -> Bool {
        guard let count = missCounts[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] else {
            return false
        }
        return count >= Self.retirementThreshold
    }

    /// The given saved order with retired identifiers left out.
    ///
    /// Use where the order is read as positions rather than moves.
    func pruning(_ sectionOrder: [String: [String]]) -> [String: [String]] {
        let retired = retiredIdentifiers
        guard !retired.isEmpty else {
            return sectionOrder
        }
        return sectionOrder.mapValues { identifiers in
            identifiers.filter { identifier in
                !retired.contains(MenuBarItemTag.canonicalPersistentIdentifier(identifier))
            }
        }
    }

    // MARK: Recording

    /// Records the outcome of one completed apply.
    ///
    /// Call only from an apply that actually planned against the bar; an
    /// early return would count a skipped pass as evidence of absence.
    ///
    /// - Parameters:
    ///   - planned: Every identifier the layout asked for, control items
    ///     excluded.
    ///   - matched: The subset of `planned` that resolved to a live item.
    ///
    /// - Returns: The identifiers newly retired by this apply, for logging.
    ///   Already-retired identifiers are not returned again.
    @discardableResult
    func recordApply(planned: Set<String>, matched: Set<String>) -> Set<String> {
        guard !planned.isEmpty else {
            return []
        }

        let unmatched = planned.subtracting(matched)
        let fraction = Double(unmatched.count) / Double(planned.count)
        guard fraction <= Self.maxUnmatchedFraction else {
            Self.diagLog.debug(
                "Discarding sample: \(unmatched.count)/\(planned.count) planned identifiers unmatched, above the \(Self.maxUnmatchedFraction) ceiling"
            )
            return []
        }

        var newlyRetired = Set<String>()
        var changed = false

        for identifier in matched {
            let key = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
            guard missCounts.removeValue(forKey: key) != nil else {
                continue
            }
            changed = true
        }

        for identifier in unmatched where Self.isRetirable(identifier) {
            let key = MenuBarItemTag.canonicalPersistentIdentifier(identifier)
            let previous = missCounts[key] ?? 0
            guard previous < Self.retirementThreshold else {
                continue
            }
            let count = previous + 1
            missCounts[key] = count
            changed = true
            if count >= Self.retirementThreshold {
                newlyRetired.insert(key)
            }
        }

        if changed {
            persist()
        }
        for key in newlyRetired {
            Self.diagLog.info("Retiring \(key): unmatched by \(Self.retirementThreshold) consecutive applies")
        }
        return newlyRetired
    }

    func removeAll() {
        guard !missCounts.isEmpty else {
            return
        }
        missCounts.removeAll()
        persist()
    }

    // MARK: Helpers

    /// Whether an identifier can meaningfully be counted at all.
    ///
    /// UUID namespaces are reassigned every session, so they never match.
    private static func isRetirable(_ identifier: String) -> Bool {
        guard let namespace = identifier.split(separator: ":", maxSplits: 1).first else {
            return false
        }
        return UUID(uuidString: String(namespace)) == nil
    }

    private func persist() {
        // Stamped on every write, including empty, so it matches the counts.
        Defaults.set(Self.currentBuildVersion, forKey: .staleIdentifierMissCountsBuild)
        if missCounts.isEmpty {
            Defaults.removeObject(forKey: .staleIdentifierMissCounts)
        } else {
            Defaults.set(missCounts, forKey: .staleIdentifierMissCounts)
        }
    }
}
