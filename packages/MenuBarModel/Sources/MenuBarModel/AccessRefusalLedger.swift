//
//  AccessRefusalLedger.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// The apps that keep answering this process's Accessibility reads with "API disabled".
/// After the system's permission service fails at login they refuse this process for as long as it runs. See AccessRefusalRecovery.
public struct AccessRefusalLedger: Sendable {
    private var refusingSince: [pid_t: ContinuousClock.Instant] = [:]

    public init() {}

    /// The owner refused a read. The time of its first refusal since it last answered is kept.
    public mutating func refused(_ owner: pid_t, at now: ContinuousClock.Instant) {
        if refusingSince[owner] == nil {
            refusingSince[owner] = now
        }
    }

    /// The owner answered a read with anything else, so it is not refusing.
    public mutating func answered(_ owner: pid_t) {
        refusingSince[owner] = nil
    }

    /// Forgets the owners that have quit.
    public mutating func retain(running: Set<pid_t>) {
        refusingSince = refusingSince.filter { running.contains($0.key) }
    }

    /// The owners that first refused at least this long ago and have not answered since.
    public func refusers(lasting duration: Duration, now: ContinuousClock.Instant) -> Set<pid_t> {
        Set(refusingSince.filter { now - $0.value >= duration }.keys)
    }
}

/// Whether Thaw should start again because other apps refuse its Accessibility reads.
public enum AccessRefusalRecovery {
    /// One app can refuse for a reason of its own, so it takes two, and at least half of the
    /// running apps that had items before, to point at this process.
    public static let minimumOwners = 2

    /// How long an app must have refused. An app that is still starting can refuse for a moment.
    public static let minimumDuration = Duration.seconds(10)

    /// What is known when the question is asked.
    public struct Facts: Sendable {
        /// How many apps that had menu bar items before still refuse this process's reads.
        public var refusers: Int
        /// How many running apps had menu bar items before, the refusing ones included.
        public var formerHosts: Int
        /// Whether the system says this process has the Accessibility permission.
        public var processTrusted: Bool
        /// Whether a helper process started later was allowed to read. If not, the permission is missing.
        public var helperTrusted: Bool
        /// Whether this copy was itself started by a restart. It does not restart again.
        public var startedByRestart: Bool

        public init(refusers: Int, formerHosts: Int, processTrusted: Bool, helperTrusted: Bool, startedByRestart: Bool) {
            self.refusers = refusers
            self.formerHosts = formerHosts
            self.processTrusted = processTrusted
            self.helperTrusted = helperTrusted
            self.startedByRestart = startedByRestart
        }
    }

    /// True when the permission is granted, a newer process can read, and enough apps still refuse this one.
    public static func shouldRestart(_ facts: Facts) -> Bool {
        guard !facts.startedByRestart, facts.processTrusted, facts.helperTrusted else { return false }
        return facts.refusers >= minimumOwners && facts.refusers * 2 >= facts.formerHosts
    }
}
