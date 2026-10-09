//
//  RepublishAbsenceMemo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Which Visible members MenuBarAgent did not republish in time, and when each was last missing.
///
/// The ordering pass waits up to three seconds for every authored member to be live. Without
/// this, each following pass spends the same deadline on the same absentee. Entries expire so
/// a member that returns is waited for again.
nonisolated struct RepublishAbsenceMemo {
    /// How long a failed republish is remembered.
    static let memory: Duration = .seconds(10)

    private var missingSince: [String: ContinuousClock.Instant] = [:]

    var count: Int { missingSince.count }

    var isEmpty: Bool { missingSince.isEmpty }

    /// Whether this member was missing recently enough that a pass should not wait for it.
    func isKnownAbsent(_ identifier: String) -> Bool {
        missingSince[identifier] != nil
    }

    /// Drops every entry older than the memory window.
    mutating func expire(now: ContinuousClock.Instant = .now) {
        missingSince = missingSince.filter { $0.value.duration(to: now) < Self.memory }
    }

    /// Forgets members that are live again.
    mutating func noteArrived(_ identifiers: some Sequence<String>) {
        for identifier in identifiers {
            missingSince.removeValue(forKey: identifier)
        }
    }

    /// Stamps members that never republished, restarting the window for any already held.
    mutating func noteMissing(_ identifiers: some Sequence<String>, at now: ContinuousClock.Instant = .now) {
        for identifier in identifiers {
            missingSince[identifier] = now
        }
    }

    /// Empties the memo so the next pass waits for every member again.
    mutating func forget() {
        missingSince.removeAll()
    }
}
