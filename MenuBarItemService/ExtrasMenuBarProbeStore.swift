//
//  ExtrasMenuBarProbeStore.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Reads and writes ``ExtrasMenuBarProbeMemory``'s contents.
///
/// Stored in the service's own defaults domain
/// (`com.stonerl.Thaw.MenuBarItemService`), not the app's: it is a
/// measurement, not a user setting, and losing it costs one slow scan.
nonisolated enum ExtrasMenuBarProbeStore {
    private static let key = "ExtrasMenuBarProbeMisses"

    private static let diagLog = DiagLog(category: "ExtrasMenuBarProbeStore")

    /// The remembered consecutive-miss count per bundle identifier.
    static func load() -> [String: Int] {
        stored()
    }

    /// Writes `misses`, unless it matches what is already stored.
    ///
    /// The write guard makes this safe to call from cache cleanup, which runs
    /// on every process launch or exit (about every nine seconds).
    static func save(_ misses: [String: Int]) {
        guard misses != stored() else {
            return
        }
        UserDefaults.standard.set(misses, forKey: key)
        diagLog.debug("Stored extras-bar probe memory for \(misses.count) applications")
    }

    private static func stored() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }
}
