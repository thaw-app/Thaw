//
//  RepublishAbsenceMemo.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Which Visible members MenuBarAgent did not republish in time, when each was last missing, and
/// which of them a pass has yet to place.
///
/// The ordering pass waits up to three seconds for every authored member to be live. Without
/// this, each following pass spends the same deadline on the same absentee. Entries expire so
/// a member that returns is waited for again.
///
/// A member the pass gave up on is left out of its write. That is kept for longer, until a pass
/// sees the member live, so LeftOutMemberWatch can have it placed when it shows up.
nonisolated struct RepublishAbsenceMemo {
    /// How long a failed republish is remembered.
    static let memory: Duration = .seconds(10)

    /// How long a member left out of a pass is watched for, from the last pass that left it out.
    static let leftOutMemory: Duration = .seconds(120)

    private var missingSince: [String: ContinuousClock.Instant] = [:]
    private var leftOutSince: [String: ContinuousClock.Instant] = [:]

    /// Counts the watches started for left-out members, so an older watch can tell it was replaced.
    private(set) var watchGeneration = 0

    var count: Int {
        missingSince.count
    }

    var isEmpty: Bool {
        missingSince.isEmpty
    }

    /// Whether this member was missing recently enough that a pass should not wait for it.
    func isKnownAbsent(_ identifier: String) -> Bool {
        missingSince[identifier] != nil
    }

    /// Drops every entry older than its memory window.
    mutating func expire(now: ContinuousClock.Instant = .now) {
        missingSince = missingSince.filter { $0.value.duration(to: now) < Self.memory }
        leftOutSince = leftOutSince.filter { $0.value.duration(to: now) < Self.leftOutMemory }
    }

    /// When the latest pass that saw any of its members live took its order, so a pass that took
    /// it before a profile was applied can't end that profile's hold. A read that returned nothing
    /// names no one missing, so it can't say the members are back.
    private(set) var lastSawMembers: ContinuousClock.Instant?

    /// Forgets members that are live again. The pass that sees them live places them. `now` is
    /// when that pass took its order; a pass that finishes late can't move lastSawMembers back.
    mutating func noteArrived(_ identifiers: some Sequence<String>, at now: ContinuousClock.Instant = .now) {
        for identifier in identifiers {
            missingSince.removeValue(forKey: identifier)
            leftOutSince.removeValue(forKey: identifier)
            lastSawMembers = max(lastSawMembers ?? now, now)
        }
    }

    /// Stamps members that never republished, which the pass then leaves out, restarting the
    /// windows for any already held.
    mutating func noteMissing(_ identifiers: some Sequence<String>, at now: ContinuousClock.Instant = .now) {
        for identifier in identifiers {
            missingSince[identifier] = now
            leftOutSince[identifier] = now
        }
    }

    /// Whether a member left out within the left-out window still waits for a pass to place it.
    func hasLeftOutMembers(now: ContinuousClock.Instant = .now) -> Bool {
        leftOutSince.values.contains { $0.duration(to: now) < Self.leftOutMemory }
    }

    /// The members left out within the left-out window that are among the live identifiers.
    func leftOutMembers(amongLive live: Set<String>, now: ContinuousClock.Instant = .now) -> Set<String> {
        Set(leftOutSince.filter { live.contains($0.key) && $0.value.duration(to: now) < Self.leftOutMemory }.keys)
    }

    /// Starts a new watch generation. A watch from an earlier one stops at its next look.
    mutating func startWatch() -> Int {
        watchGeneration += 1
        return watchGeneration
    }

    /// The wanted members a read shows as gone. An empty read saw nothing, as a cancelled one
    /// does, so it names nobody.
    static func absentees(wanted: Set<String>, live: Set<String>) -> Set<String> {
        live.isEmpty ? [] : wanted.subtracting(live)
    }

    /// The wanted members nothing can republish: their app has no item on the bar and is not
    /// running, as when an app was removed or changed its bundle identifier. A running app may
    /// still publish, so it is waited for. Members not named by a bundle identifier are kept.
    static func unreachable(wanted: Set<String>, liveNamespaces: Set<String>, runningBundleIDs: Set<String>) -> Set<String> {
        wanted.filter { identifier in
            let namespace = MenuBarItemTag.persistentIdentifierParts(identifier)?.namespace ?? identifier
            return namespace.contains(".") && !liveNamespaces.contains(namespace) && !runningBundleIDs.contains(namespace)
        }
    }

    /// The missing members worth a warning: those whose app is running or still has an item on the bar.
    static func reportable(_ missing: Set<String>, liveNamespaces: Set<String>, runningBundleIDs: Set<String>) -> Set<String> {
        missing.subtracting(unreachable(wanted: missing, liveNamespaces: liveNamespaces, runningBundleIDs: runningBundleIDs))
    }

    /// Forgets the absences so the next pass waits for every member again. Left-out members stay
    /// watched; that pass places them or leaves them out again.
    mutating func forget() {
        missingSince.removeAll()
    }
}
