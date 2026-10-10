//
//  SignatureStabilityGate.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Holds a changed item signature until it has stayed the same for a grace period.
///
/// On macOS 27 a signature can differ from the cache for a moment without the bar having
/// changed: a dynamic-title app drops its AX subtree, or a marker or clone window flickers
/// during a reflow. Recaching on each of those reorders icons and re-applies the assertion,
/// and two quick samples are not enough to tell them apart. A real change holds past the
/// grace; a flap returns to the cached signature and clears the gate.
nonisolated struct SignatureStabilityGate {
    /// The differing signature being waited on, if any.
    private(set) var candidate: [String]?
    /// When the candidate was first seen. It confirms once it has held since then for the grace.
    private(set) var firstSeen: ContinuousClock.Instant?

    /// True while a difference is waiting out its grace.
    var isPending: Bool {
        candidate != nil
    }

    /// Scores one sample and says whether to recache now.
    ///
    /// A match with the cache clears the gate. A first sighting, or a difference that itself
    /// changed, starts the clock. The same difference held for the grace recaches and clears.
    mutating func shouldRecache(
        cached: [String],
        current: [String],
        now: ContinuousClock.Instant = .now,
        grace: Duration
    ) -> Bool {
        guard current != cached else {
            candidate = nil
            firstSeen = nil
            return false
        }
        if let candidate, let firstSeen, candidate == current {
            guard now - firstSeen >= grace else { return false }
            self.candidate = nil
            self.firstSeen = nil
            return true
        }
        candidate = current
        firstSeen = now
        return false
    }
}
