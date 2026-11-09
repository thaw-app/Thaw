//
//  WriteHold.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Reasons a write pass holds off, checked in a caller-given order.
nonisolated enum WriteHold {
    /// A condition a write pass can hold on, named after the condition.
    enum Check: String, CaseIterable {
        case startupSettling
        case circuitBreakerOpen
        case notificationCenterSuspended
        case userDragging
        case profileApplying
        case membershipReadPending
        /// The layout publication is forbidden, so reads would show an old bar.
        case layoutPublicationStale
        case sectionRevealed
        case revealTransitionActive
        /// macOS moved the bar to a display the cache has not followed yet,
        /// so frames read now mix two bars.
        case barOnUncachedDisplay
        /// The cache came from a read that ran out of time or was filled in
        /// from older items, so it can be missing items that are on the bar.
        case barReadIncomplete
    }

    /// Which checks hold at one point in time, built by the calling pass.
    struct Situation {
        var startupSettling = false
        var circuitBreakerOpen = false
        var notificationCenterSuspended = false
        var userDragging = false
        var profileApplying = false
        var membershipReadPending = false
        var layoutPublicationStale = false
        var sectionRevealed = false
        var revealTransitionActive = false
        var barOnUncachedDisplay = false
        var barReadIncomplete = false

        /// Each condition paired with the check named after it.
        private var conditions: [(holds: Bool, check: Check)] {
            [
                (startupSettling, .startupSettling),
                (circuitBreakerOpen, .circuitBreakerOpen),
                (notificationCenterSuspended, .notificationCenterSuspended),
                (userDragging, .userDragging),
                (profileApplying, .profileApplying),
                (membershipReadPending, .membershipReadPending),
                (layoutPublicationStale, .layoutPublicationStale),
                (sectionRevealed, .sectionRevealed),
                (revealTransitionActive, .revealTransitionActive),
                (barOnUncachedDisplay, .barOnUncachedDisplay),
                (barReadIncomplete, .barReadIncomplete),
            ]
        }

        /// The checks whose conditions hold in this situation.
        var heldChecks: Set<Check> {
            Set(conditions.filter(\.holds).map(\.check))
        }
    }

    /// The first check in the given order whose condition holds in the
    /// situation, or nil when none do. A check missing from the list is
    /// ignored, however its condition stands.
    static func first(_ checks: [Check], in situation: Situation) -> Check? {
        let held = situation.heldChecks
        return checks.first { held.contains($0) }
    }
}

/// The holds the structural normalization pass checks, in order.
nonisolated enum StructuralNormalizationHolds {
    /// Checked after the debounce and again after repair-lane admission; a hold rearms the pass, bounded.
    /// The control-resort hold is checked apart from this list, where the pass always read it.
    static let checks: [WriteHold.Check] = [
        .layoutPublicationStale,
        .sectionRevealed,
        .revealTransitionActive,
        .barOnUncachedDisplay,
        .barReadIncomplete,
    ]

    /// The line logged when the pass defers on this check, or nil for a check it defers on quietly.
    static func deferralNote(for check: WriteHold.Check) -> String? {
        check == .barReadIncomplete ? "structural normalization: the last bar read was incomplete; deferring" : nil
    }

    static func logDeferral(on check: WriteHold.Check) {
        if let note = deferralNote(for: check) {
            MenuBarItemManager.diagLog.debug("\(note)")
        }
    }

    /// Whether a deferred pass needs a fresh full read before its retry: the bar moved to a display the
    /// cache hasn't followed, or the last read was incomplete. Nothing else asks for a read in either case.
    static func needsFreshRead(_ situation: WriteHold.Situation) -> Bool {
        situation.barOnUncachedDisplay || situation.barReadIncomplete
    }
}
