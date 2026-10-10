//
//  MenuBarItemVolatilityIndex.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Reuse pixel comparisons to guide caching; unknown items need fresh captures until observations establish stability.
/// Persist stable tagIdentifier keys to accrue observations across sessions with open consumers; unstable namespaces stay in memory.
@MainActor
final class MenuBarItemVolatilityIndex {
    /// How an item behaves across refreshes.
    enum Volatility: String {
        /// Insufficient observations; callers must not treat this as stable.
        case unknown

        /// Observed repeatedly and never seen to change. Wi-Fi, Bluetooth, and
        /// most third-party status glyphs land here.
        case stable

        /// Changes, but not on most refreshes. Battery percentage, sync badges.
        case occasional

        /// Changes on most refreshes, such as clocks, CPU meters, or network readouts.
        case live
    }

    enum Thresholds {
        /// Observations required before an item is classified at all.
        static let minimumObservations = 12

        /// Consecutive unchanged observations required to call an item stable.
        static let stableStreak = 24

        /// Change rate at or above which an item is called Volatility.live.
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

        /// Last captured width in points; optional for compatibility with records lacking this field.
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
            // Preserve the ratio without overflowing counters in long sessions.
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

    /// Bump version when old tallies become misleading; a mismatch drops the store.
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

    /// Call once per item per refresh, including unchanged images, to measure stability.
    func record(tag: MenuBarItemTag, changed: Bool, width: CGFloat? = nil) {
        observationsRecorded += 1
        let key = tag.tagIdentifier
        records[key, default: Record()].record(changed: changed, width: width.map(Double.init))
        if case .string = tag.namespace {
            persistableKeys.insert(key)
        }
    }

    /// Snapshot by tagIdentifier for off-main-actor disk loading without per-item actor hops.
    func classificationsByKey() -> [String: Volatility] {
        records.mapValues(\.volatility)
    }

    /// Prunes absent items from memory to bound growth from quit apps.
    /// Persisted records age out by lifetime so section toggles retain history.
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

    /// Logs stability distribution to assess the value of overlays and long-lived disk caching.
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

        // Log periodically even when counts match, to distinguish settled items from resetting records.
        // Rising observations with deepest near 1 indicate cache-key churn.
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

        // Moving items require fresh captures, so their identities and count explain the cost.
        let moving = records
            .filter { $0.value.volatility == .live || $0.value.volatility == .occasional }
            .map { key, record in
                "\"\(key)\" \(record.volatility.rawValue) \(Int(record.changeRate * 100))%"
            }
            .sorted()
        if !moving.isEmpty {
            Self.diagLog.notice("Volatility: moving → \(moving.joined(separator: ", "))")
        }

        // Share the log throttle to limit persistence writes after counters change.
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
