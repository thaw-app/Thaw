//
//  ClickAttemptPolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The decisions behind one menu bar item click: how many synthetic attempts the owner gets,
/// what a quiet press that did not open anything means, and what follows a failed attempt.
///
/// The click itself posts events and reads the bar, so it can only run against a live menu
/// bar. These functions take plain inputs and return the decision, so the caller only acts
/// on it.
enum ClickAttemptPolicy {
    /// How many synthetic click attempts an item gets.
    ///
    /// An owner already known to ignore synthetic events gets one attempt instead of
    /// several. Retrying it only repeats the cursor warp that the user sees as the item
    /// jittering, and the extra attempts have never been what makes such an owner answer.
    /// A caller asking for no attempts still gets one.
    static func attemptBudget(ownerUnresponsive: Bool, maxAttempts: Int) -> Int {
        ownerUnresponsive ? 1 : max(1, maxAttempts)
    }

    /// What to do with a quiet press that did not fail outright.
    enum PressOutcome: Equatable {
        /// The owner reacted: the click is done.
        case opened
        /// The owner took the press and showed nothing, and the caller does not need a
        /// reaction: return as it is rather than toggle the item a second time.
        case acceptWithoutReaction
        /// The owner took the press and showed nothing, and the caller needs a reaction: post
        /// a real click.
        case postRealClick
    }

    /// Judges the result of a press made without synthesizing events.
    static func pressOutcome(didReact: Bool, requireObservedReaction: Bool) -> PressOutcome {
        if didReact {
            return .opened
        }
        return requireObservedReaction ? .postRealClick : .acceptWithoutReaction
    }

    /// Why a click attempt failed, as far as the retry decision cares.
    enum AttemptFailure: Equatable {
        /// The failure was thrown by the event path.
        /// - indicatesUnresponsiveOwner: Whether it says the owner stayed silent.
        case event(indicatesUnresponsiveOwner: Bool)
        /// Anything else, such as a cancellation or an error from another layer.
        case other
    }

    /// What to do after a failed click attempt.
    struct AfterFailure: Equatable {
        /// Wait and try again. When false the attempts are spent and the failure ends the click.
        let retries: Bool
        /// Whether to mark the owner unresponsive before the failure is thrown.
        let recordsUnresponsiveOwner: Bool
        /// Whether to throw the catch-all error instead of the failure itself, because it did
        /// not come from the event path.
        let reportsCannotComplete: Bool

        static let retry = AfterFailure(
            retries: true, recordsUnresponsiveOwner: false, reportsCannotComplete: false
        )
    }

    /// Decides what follows a failed attempt.
    ///
    /// Only the last attempt's failure is reported or recorded. Earlier ones are retried
    /// whatever they were, so one slow owner does not get marked on its first miss.
    static func afterFailure(attempt: Int, budget: Int, failure: AttemptFailure) -> AfterFailure {
        guard attempt >= budget else {
            return .retry
        }
        switch failure {
        case let .event(indicatesUnresponsiveOwner):
            return AfterFailure(
                retries: false, recordsUnresponsiveOwner: indicatesUnresponsiveOwner, reportsCannotComplete: false
            )
        case .other:
            return AfterFailure(retries: false, recordsUnresponsiveOwner: false, reportsCannotComplete: true)
        }
    }
}

extension MenuBarItemManager.EventError {
    /// This error as the retry decision sees it.
    var attemptFailure: ClickAttemptPolicy.AttemptFailure {
        .event(indicatesUnresponsiveOwner: indicatesUnresponsiveOwner)
    }
}
