//
//  WriteHold.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// One write pass's reasons to hold off writing the menu bar, checked through
/// one gate: the pass builds a situation from its own flags and asks which of
/// its named checks holds first. Pure values, so the lists are testable.
nonisolated enum WriteHold {
    /// A condition a write pass can hold on, named after the condition.
    enum Check: String, CaseIterable {
        /// The app is still settling at startup.
        case startupSettling
        /// The move circuit breaker is open.
        case circuitBreakerOpen
        /// Notification Center has suspended menu bar layout.
        case notificationCenterSuspended
        /// The user is dragging a menu bar item.
        case userDragging
        /// A profile layout is being applied.
        case profileApplying
        /// Arrangement is manual and the stranded-control exception does not apply.
        case manualArrangement
        /// A membership read of a ⌘-drag is still pending.
        case membershipReadPending
        /// The layout publication is forbidden, so reads would show an old bar.
        case layoutPublicationStale
        /// A section is revealed.
        case sectionRevealed
        /// A reveal or hide transition is active.
        case revealTransitionActive
    }

    /// Which checks hold at one point in time, built by the calling pass.
    struct Situation {
        var startupSettling = false
        var circuitBreakerOpen = false
        var notificationCenterSuspended = false
        var userDragging = false
        var profileApplying = false
        var manualArrangement = false
        var membershipReadPending = false
        var layoutPublicationStale = false
        var sectionRevealed = false
        var revealTransitionActive = false

        /// Each condition paired with the check named after it.
        private var conditions: [(holds: Bool, check: Check)] {
            [
                (startupSettling, .startupSettling),
                (circuitBreakerOpen, .circuitBreakerOpen),
                (notificationCenterSuspended, .notificationCenterSuspended),
                (userDragging, .userDragging),
                (profileApplying, .profileApplying),
                (manualArrangement, .manualArrangement),
                (membershipReadPending, .membershipReadPending),
                (layoutPublicationStale, .layoutPublicationStale),
                (sectionRevealed, .sectionRevealed),
                (revealTransitionActive, .revealTransitionActive),
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
