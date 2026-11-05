//
//  ProfileSwitchBacklog.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ThawModuleKit

/// The profile switch the Scripts module hasn't heard: held while it starts or restarts, and sent
/// once it says it listens. Holding instead of also sending means no switch runs its scripts twice.
nonisolated struct ProfileSwitchBacklog {
    /// A held switch older than this is dropped, so turning Scripts on later runs nothing stale.
    static let maximumAge = Duration.seconds(60)

    private(set) var isListening = false
    private var held: [(phase: ProfileSwitch.Phase, event: ProfileSwitch, at: ContinuousClock.Instant)] = []

    /// Whether to send this phase now. Otherwise it is held, and a new switch replaces the one held.
    mutating func shouldSend(_ phase: ProfileSwitch.Phase, _ event: ProfileSwitch, at now: ContinuousClock.Instant) -> Bool {
        if isListening {
            return true
        }
        if phase == .willApply {
            held.removeAll()
        }
        held.append((phase, event, now))
        return false
    }

    /// The module listens now: the held phases still recent enough to run, oldest first.
    mutating func moduleListening(at now: ContinuousClock.Instant) -> [(phase: ProfileSwitch.Phase, event: ProfileSwitch)] {
        isListening = true
        let due = held.filter { now - $0.at <= Self.maximumAge }.map { ($0.phase, $0.event) }
        held.removeAll()
        return due
    }

    /// The module quit, so switches are held until it listens again.
    mutating func moduleStopped() {
        isListening = false
    }
}
