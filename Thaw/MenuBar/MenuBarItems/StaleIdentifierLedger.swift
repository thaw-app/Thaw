//
//  StaleIdentifierLedger.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - StaleIdentifierLedger

/// The record of which saved identifiers have stopped corresponding to
/// anything on the bar, so that a layout can eventually stop planning
/// against them.
///
/// A saved order accumulates identifiers and never sheds them. That is
/// deliberate for the common case: `planSectionOrder` merges entries for
/// apps that are merely closed, because forgetting them would send an app
/// back to `NewItemsPlacement` the next time it launched instead of the
/// slot the user put it in. So "no live item matches this identifier"
/// cannot, on its own, mean the identifier is dead.
///
/// It stops being deliberate when the identity itself is gone. An app that
/// changes its bundle identifier — #899's reporter carried
/// `de.simon.RAMTamer` alongside `de.simon.ramtamer`, and the same pair for
/// JuicyFlow — leaves an entry behind that no future item can ever match,
/// because nothing anywhere records that one bundle identifier superseded
/// another. Canonicalization does not merge them either: it only rewrites
/// the volatile-title owners, so the two spellings stay distinct forever.
///
/// Such an entry costs nothing at move-planning time — the apply filters the
/// desired sequence down to identifiers that are actually on the bar, so a
/// dead one is simply skipped and never becomes an unenacted move. What it
/// costs is *position*. ``LayoutSolver/savedPositionByBaseID(for:in:)``
/// answers with an index into the saved array, and every dead entry ahead of
/// a live one inflates that index. An app that returns to the bar is then
/// placed further right than the user left it, by exactly the number of
/// ghosts in front of it — and because nothing ever removes them, the drift
/// only grows.
///
/// The only signal that separates the two cases is repetition. A closed app
/// comes back; a retired identity does not. This ledger counts consecutive
/// applies in which an identifier was planned and went unmatched, and names
/// the ones that have run out of excuses.
///
/// It never deletes anything. Retirement means "stop counting it when
/// resolving saved positions", which leaves the entry in the user's saved
/// order and in their profile file, and lets one live match undo the verdict
/// at any time. That matters because the verdict can be wrong: an item whose
/// owner Thaw cannot yet attribute — Little Snitch's agent before its marker
/// window appears — is indistinguishable from a rename here. Retiring it
/// costs nothing, because it is unplaceable either way, and the moment the
/// marker resolves the identifier matches again and the count is cleared.
@MainActor
final class StaleIdentifierLedger {
    /// How many consecutive unmatched applies retire an identifier.
    ///
    /// Sized against the case it must not break: an app the user quits for
    /// an afternoon. Applies are driven by cache cycles and profile
    /// switches, not by a timer, so this is a count of opportunities rather
    /// than a duration — but it has to be large enough that ordinary
    /// quit-and-relaunch never reaches it, and small enough that a genuine
    /// rename is retired within a session or two of normal use.
    static let retirementThreshold = 10

    /// The largest share of a planned order that may go unmatched before the
    /// sample is discarded.
    ///
    /// ``MenuBarItemManager`` already abandons an apply when the majority of
    /// source PIDs are unresolved, but partial degradation clears that bar
    /// while still mislabelling a third of the bar as absent. Counting those
    /// applies would retire real items in batches — the exact failure this
    /// ledger would be blamed for, and the one that is hardest to diagnose
    /// afterwards, because the evidence is the thing that got deleted.
    ///
    /// A quarter is above anything a working bar produces (closed apps are a
    /// handful of entries, not a quarter of them) and well below what a
    /// degraded resolution pass produces.
    static let maxUnmatchedFraction = 0.25

    private static nonisolated let diagLog = DiagLog(category: "StaleIdentifierLedger")

    /// The build string persisted counts are valid for; a change drops them.
    ///
    /// Identity resolution is the thing most likely to improve between
    /// builds — a Control-Center-hosted item that never resolved under one
    /// release starts resolving under the next. Counts earned against the
    /// old behaviour would retire identifiers the new build can match, so an
    /// update clears the slate.
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
    /// Takes the raw identifier and canonicalizes it here, so a caller
    /// holding an entry from a saved order cannot check a different key than
    /// ``recordApply(planned:matched:)`` recorded under.
    func isRetired(_ identifier: String) -> Bool {
        guard let count = missCounts[MenuBarItemTag.canonicalPersistentIdentifier(identifier)] else {
            return false
        }
        return count >= Self.retirementThreshold
    }

    /// The given saved order with retired identifiers left out.
    ///
    /// Apply this where the order is read as *positions* rather than as a
    /// list of things to move: a ghost ahead of a live entry inflates the
    /// index ``LayoutSolver/savedPositionByBaseID(for:in:)`` reports, which is
    /// the drift this ledger exists to stop. An order with nothing retired in
    /// it comes back untouched.
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
    /// Call this only from an apply that actually planned against the bar.
    /// An apply that returned early — no item order, no control items, a
    /// menu open, a majority of source PIDs unresolved — observed nothing
    /// about any identifier, and feeding it here would count a skipped pass
    /// as evidence of absence.
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
                continue // Already retired; leave the count where it is.
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

    /// Forgets everything, so that a reset starts from no verdicts.
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
    /// A UUID namespace is reassigned every session, so such an entry is
    /// unmatched on every apply for a reason that has nothing to do with the
    /// item having gone away. Counting it would retire it on its tenth apply
    /// and teach the ledger nothing.
    private static func isRetirable(_ identifier: String) -> Bool {
        guard let namespace = identifier.split(separator: ":", maxSplits: 1).first else {
            return false
        }
        return UUID(uuidString: String(namespace)) == nil
    }

    private func persist() {
        // Stamped on every write, including the empty one, so the stamp and
        // the counts it describes can never disagree.
        Defaults.set(Self.currentBuildVersion, forKey: .staleIdentifierMissCountsBuild)
        if missCounts.isEmpty {
            Defaults.removeObject(forKey: .staleIdentifierMissCounts)
        } else {
            Defaults.set(missCounts, forKey: .staleIdentifierMissCounts)
        }
    }
}
