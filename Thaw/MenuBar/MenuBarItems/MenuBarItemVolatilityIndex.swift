//
//  MenuBarItemVolatilityIndex.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Per-item record of how often a menu bar item's rendered image actually
/// changes.
///
/// `MenuBarItemImageCache`'s refresh path already pixel-compares each new
/// capture against the cached image so it can store only the ones that moved.
/// That comparison is the entire signal this index needs, and it is already
/// paid for — the cache simply discarded the per-item answer and logged an
/// aggregate count.
///
/// Recording it turns the image cache from a flat TTL blob into something
/// closer to an index: most items are known-static almost all of the time, so
/// heavy work (long-lived disk persistence, trusting a cached image during a
/// transition) can be reserved for the few that are not.
///
/// The classification is deliberately an observation, never a prediction. An
/// item is only called ``Volatility/stable`` after it has been *seen* to hold
/// still across ``Thresholds/minimumObservations`` refreshes; anything less is
/// ``Volatility/unknown`` and callers must fall back to their existing
/// behaviour. Being wrong in that direction is cheap (a redundant capture);
/// being wrong the other way puts a stale glyph on screen.
///
/// Records persist across launches (plan 031 step 1): observations only accrue
/// while a capture consumer is open, so a single session rarely sees enough of
/// them — persistence turns many short sessions into one long one. Keys are
/// `tagIdentifier` strings, which the 2026-07-25 identity audit showed are
/// relaunch-stable for every managed item; entries whose namespace is not
/// stable across launches are kept in memory but never persisted, mirroring
/// `MenuBarItemFailureLedger`.
@MainActor
final class MenuBarItemVolatilityIndex {
    /// How an item behaves across refreshes.
    enum Volatility: String {
        /// Not yet observed often enough to classify. Callers must not treat
        /// this as "stable" — it is the "no opinion" case.
        case unknown

        /// Observed repeatedly and never seen to change. Wi-Fi, Bluetooth, and
        /// most third-party status glyphs land here.
        case stable

        /// Changes, but not on most refreshes. Battery percentage, sync badges.
        case occasional

        /// Changes on most refreshes. Clocks, CPU meters, network throughput
        /// readouts — the items whose titles Lounge persisted and then could
        /// never match again.
        case live
    }

    enum Thresholds {
        /// Observations required before an item is classified at all.
        static let minimumObservations = 12

        /// Consecutive unchanged observations required to call an item stable.
        static let stableStreak = 24

        /// Change rate at or above which an item is called ``Volatility/live``.
        static let liveChangeRate = 0.5

        /// Persisted records unseen for this long are dropped on load.
        static let persistedRecordLifetime: TimeInterval = 14 * 24 * 60 * 60
    }

    /// Running tally for one item.
    struct Record: Codable {
        private(set) var observations = 0
        private(set) var changes = 0
        private(set) var unchangedStreak = 0
        private(set) var lastObserved = Date.distantPast

        /// Last captured width in points (plan 031 step 3 geometry). Optional
        /// so records persisted before this field existed still decode.
        private(set) var lastWidth: Double?

        /// Fraction of observations on which the image changed.
        var changeRate: Double {
            observations > 0 ? Double(changes) / Double(observations) : 0
        }

        var volatility: Volatility {
            guard observations >= Thresholds.minimumObservations else {
                return .unknown
            }
            if changeRate >= Thresholds.liveChangeRate {
                return .live
            }
            if changes == 0, unchangedStreak >= Thresholds.stableStreak {
                return .stable
            }
            return .occasional
        }

        mutating func record(changed: Bool, width: Double?) {
            // Saturate rather than overflow on a long-running session; the
            // ratio is what matters, not the absolute count.
            if observations == Int.max {
                observations /= 2
                changes /= 2
            }
            observations += 1
            lastObserved = Date()
            if let width, width > 0 {
                lastWidth = width
            }
            if changed {
                changes += 1
                unchangedStreak = 0
            } else {
                unchangedStreak += 1
            }
        }
    }

    /// On-disk envelope. Bump `version` when `Record`'s meaning changes enough
    /// that old tallies would mislead; a mismatch drops the store.
    private struct PersistedStore: Codable {
        var version: Int
        var records: [String: Record]
    }

    private static let currentStoreVersion = 1
    private static let diagLog = DiagLog(category: "MenuBarItemVolatilityIndex")

    private var records: [String: Record] = [:]

    /// Keys whose namespace survives a relaunch; only these are persisted.
    private var persistableKeys: Set<String> = []

    private var lastLoggedSummary: String?
    private var lastLoggedAt: ContinuousClock.Instant?
    private var observationsRecorded = 0
    private var recordsDroppedByPrune = 0

    init() {
        loadFromDefaults()
    }

    /// Records one refresh observation for an item.
    ///
    /// Call once per item per refresh pass, including for items that did not
    /// change — an unchanged observation is the more informative one.
    func record(tag: MenuBarItemTag, changed: Bool, width: CGFloat? = nil) {
        observationsRecorded += 1
        let key = tag.tagIdentifier
        records[key, default: Record()].record(changed: changed, width: width.map(Double.init))
        if case .string = tag.namespace {
            persistableKeys.insert(key)
        }
    }

    /// The last captured width in points for an item, if one was recorded.
    func indexedWidth(for tag: MenuBarItemTag) -> CGFloat? {
        records[tag.tagIdentifier]?.lastWidth.map { CGFloat($0) }
    }

    /// The classification for an item, or ``Volatility/unknown`` if it has not
    /// been observed enough.
    func volatility(for tag: MenuBarItemTag) -> Volatility {
        records[tag.tagIdentifier]?.volatility ?? .unknown
    }

    func record(for tag: MenuBarItemTag) -> Record? {
        records[tag.tagIdentifier]
    }

    /// Snapshot of every known classification, keyed by `tagIdentifier`.
    /// Used by the image cache's disk-load path, which runs off the main
    /// actor and needs the classifications without per-item hops.
    func classificationsByKey() -> [String: Volatility] {
        records.mapValues(\.volatility)
    }

    /// Whether an item's cached image can be trusted without a fresh capture.
    ///
    /// Only ``Volatility/stable`` qualifies. `.occasional` is deliberately
    /// excluded: an item that changes at all can change during the moment the
    /// cached image is on screen.
    func isCacheTrustworthy(for tag: MenuBarItemTag) -> Bool {
        volatility(for: tag) == .stable
    }

    /// Drops in-memory records for items no longer present, so a long session
    /// does not accumulate entries for quit applications. Persisted entries
    /// are aged out by ``Thresholds/persistedRecordLifetime`` instead, so an
    /// item that merely toggled between sections keeps its history.
    func prune(keeping tags: Set<MenuBarItemTag>) {
        guard !tags.isEmpty else { return }
        let keep = Set(tags.map(\.tagIdentifier))
        let before = records.count
        records = records.filter { keep.contains($0.key) }
        recordsDroppedByPrune += before - records.count
    }

    func removeAll() {
        records.removeAll()
        persistableKeys.removeAll()
        lastLoggedSummary = nil
        UserDefaults.standard.removeObject(forKey: Defaults.Key.menuBarItemVolatilityIndex.rawValue)
    }

    /// Logs the current distribution, throttled to once per distinct shape.
    ///
    /// This is what answers "how much of the menu bar is actually static?" —
    /// the question that decides whether the overlay and long-lived disk
    /// persistence are worth building.
    func logDistributionIfChanged() {
        guard !records.isEmpty else { return }

        var counts: [Volatility: Int] = [:]
        for record in records.values {
            counts[record.volatility, default: 0] += 1
        }

        let summary = ["unknown", "stable", "occasional", "live"]
            .compactMap { name -> String? in
                guard let volatility = Volatility(rawValue: name) else { return nil }
                return "\(name)=\(counts[volatility] ?? 0)"
            }
            .joined(separator: " ")
        let line = "total=\(records.count) \(summary)"

        // A distribution that never changes is itself a result — it can mean
        // "everything is settled" or "records keep resetting and nothing ever
        // matures". Those look identical under a content-only throttle, so
        // also emit on a timer and carry the maturity counters that tell them
        // apart: if `deepest` stays near 1 while `observations` climbs, the
        // cache key is churning rather than the items holding still.
        let now = ContinuousClock.now
        let elapsedEnough = lastLoggedAt.map { now - $0 >= .seconds(15) } ?? true
        guard line != lastLoggedSummary || elapsedEnough else { return }
        lastLoggedSummary = line
        lastLoggedAt = now

        let deepest = records.values.map(\.observations).max() ?? 0
        let shallowest = records.values.map(\.observations).min() ?? 0
        Self.diagLog.notice(
            "Volatility: depth deepest=\(deepest) shallowest=\(shallowest) "
                + "observations=\(self.observationsRecorded) prunedRecords=\(self.recordsDroppedByPrune)"
        )

        Self.diagLog.notice("Volatility: \(line)")

        // Name the moving items — they are the ones any cached-image
        // presentation has to capture fresh, so their count and identity is
        // the cost driver.
        let moving = records
            .filter { $0.value.volatility == .live || $0.value.volatility == .occasional }
            .map { key, record in
                "\"\(key)\" \(record.volatility.rawValue) \(Int(record.changeRate * 100))%"
            }
            .sorted()
        if !moving.isEmpty {
            Self.diagLog.notice("Volatility: moving → \(moving.joined(separator: ", "))")
        }

        // Piggyback persistence on the log throttle: at most one write per
        // 15 s while the refresh loop runs, and always after the counters
        // above already changed.
        saveToDefaults()
    }

    // MARK: Persistence

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(
            forKey: Defaults.Key.menuBarItemVolatilityIndex.rawValue
        ) else {
            return
        }
        let store: PersistedStore
        do {
            store = try JSONDecoder().decode(PersistedStore.self, from: data)
        } catch {
            Self.diagLog.error("Volatility: failed to decode persisted store: \(error)")
            return
        }
        guard store.version == Self.currentStoreVersion else {
            Self.diagLog.notice(
                "Volatility: dropping persisted store (version \(store.version) != \(Self.currentStoreVersion))"
            )
            UserDefaults.standard.removeObject(forKey: Defaults.Key.menuBarItemVolatilityIndex.rawValue)
            return
        }
        let cutoff = Date().addingTimeInterval(-Thresholds.persistedRecordLifetime)
        records = store.records.filter { $0.value.lastObserved > cutoff }
        persistableKeys = Set(records.keys)
        if !records.isEmpty {
            Self.diagLog.notice("Volatility: loaded \(self.records.count) persisted record(s)")
        }
    }

    private func saveToDefaults() {
        let persistable = records.filter { persistableKeys.contains($0.key) }
        guard !persistable.isEmpty else { return }
        let store = PersistedStore(version: Self.currentStoreVersion, records: persistable)
        do {
            let data = try JSONEncoder().encode(store)
            UserDefaults.standard.set(data, forKey: Defaults.Key.menuBarItemVolatilityIndex.rawValue)
        } catch {
            Self.diagLog.error("Volatility: failed to encode store: \(error)")
        }
    }
}
