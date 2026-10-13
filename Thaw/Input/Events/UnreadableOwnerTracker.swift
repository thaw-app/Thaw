//
//  UnreadableOwnerTracker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin

/// Finds apps the bar draws but the walk keeps missing: MenuBarAgent's window
/// names them without asking them, so those are refusing accessibility reads.
nonisolated struct UnreadableOwnerTracker {
    /// One miss is a reveal still settling; this many in a row is not.
    static let missesBeforeReporting = 3

    struct Change: Equatable {
        var unreadable: Set<pid_t> = []
        var readableAgain: Set<pid_t> = []
    }

    private var misses: [pid_t: Int] = [:]
    private(set) var reported: Set<pid_t> = []

    /// Each owner is returned once when it turns unreadable and once when it recovers.
    mutating func note(drawn: Set<pid_t>, read: Set<pid_t>) -> Change {
        var change = Change()
        let missing = drawn.subtracting(read)
        for pid in Set(misses.keys).subtracting(missing) {
            misses[pid] = nil
            if reported.remove(pid) != nil, drawn.contains(pid) {
                change.readableAgain.insert(pid)
            }
        }
        for pid in missing {
            misses[pid, default: 0] += 1
            if misses[pid] == Self.missesBeforeReporting, reported.insert(pid).inserted {
                change.unreadable.insert(pid)
            }
        }
        return change
    }
}
