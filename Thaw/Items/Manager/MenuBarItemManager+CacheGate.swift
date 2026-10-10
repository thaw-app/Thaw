//
//  MenuBarItemManager+CacheGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

extension MenuBarItemManager {
    /// Serializes cache passes so concurrent scans cannot cache pre-relocation positions in the wrong section.
    /// Coalesces concurrent requests into a follow-up pass.
    actor CacheGate {
        private var isInProgress = false
        private var rerunRequested = false

        /// Returns false while a pass is in flight and requests one coalesced rerun at completion.
        func begin() -> Bool {
            guard !isInProgress else {
                rerunRequested = true
                return false
            }
            isInProgress = true
            return true
        }

        /// Ends the current pass and returns whether a rerun was requested while
        /// it was in flight (cleared on read).
        func end() -> Bool {
            isInProgress = false
            let rerun = rerunRequested
            rerunRequested = false
            return rerun
        }
    }
}
