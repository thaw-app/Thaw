//
//  ExtrasMenuBarProbeStore.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Reads and writes ``ExtrasMenuBarProbeMemory``'s contents.
///
/// The service has no access to the app's `Defaults`, and does not need it:
/// this memory is written by the process that does the probing and read by
/// nobody else, so it lives in the service's own defaults domain
/// (`com.stonerl.Thaw.MenuBarItemService`). Keeping it out of the app's
/// domain also keeps it out of everything that treats that domain as user
/// settings — this is a measurement, not a preference, and losing it costs
/// one slow scan.
nonisolated enum ExtrasMenuBarProbeStore {
    private static let key = "ExtrasMenuBarProbeMisses"

    private static let diagLog = DiagLog(category: "ExtrasMenuBarProbeStore")

    /// The remembered consecutive-miss count per bundle identifier.
    static func load() -> [String: Int] {
        stored()
    }

    /// Writes `misses`, unless it matches what is already stored.
    ///
    /// The write guard is what makes it safe to call this from the cache
    /// cleanup, which runs whenever any process on the system starts or exits
    /// — roughly every nine seconds in the field. The memory converges within
    /// the first minute of a session and then stops changing.
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
