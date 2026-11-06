//
//  DeferredLayoutReconcileSchedule.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The one pending retry of the saved-layout reconciler, and how often it has been put off.
///
/// applySavedLayout declines for reasons that clear on their own: a move cooldown, the
/// restriction-reflow settle window, an in-flight drag. While the user is editing, every drop
/// re-arms those windows, so waiting for a cache cycle to land in a clear one would never run
/// the reconciler. Retrying when the blocking window expires turns a decline into a deferral.
/// The deferrals are counted because a reconcile whose own moves re-arm the move cooldown
/// would otherwise put itself off forever.
nonisolated struct DeferredLayoutReconcileSchedule {
    /// Deferrals in a row allowed before giving up until the reconciler next runs.
    static let limit = 5

    private var task: Task<Void, Never>?
    private var due: ContinuousClock.Instant?

    /// Deferrals in a row without the reconciler managing to run.
    private(set) var deferrals = 0

    /// Whether a retry is armed and has not yet fired.
    var isPending: Bool {
        task != nil
    }

    /// Claims a retry delay from now, and returns when it is due, or nil when no new retry
    /// should be armed: the limit is reached, or a pending retry is already due no later. A
    /// claim counts as one deferral and cancels the retry it replaces.
    mutating func claim(
        after delay: Duration,
        limit: Int = Self.limit,
        now: ContinuousClock.Instant = .now
    ) -> ContinuousClock.Instant? {
        guard deferrals < limit else { return nil }
        let candidate = now + delay
        if let due, task != nil, due <= candidate {
            return nil
        }
        task?.cancel()
        task = nil
        due = candidate
        deferrals += 1
        return candidate
    }

    /// Holds the task that waits out a claimed retry.
    mutating func arm(_ task: Task<Void, Never>) {
        self.task = task
    }

    /// Notes that the retry's wait is over and it is about to run. The count stands until the
    /// reconciler itself gets to run.
    mutating func fired() {
        task = nil
        due = nil
    }

    /// Cancels the pending retry and keeps the count, as when layout work is suspended.
    mutating func cancelPending() {
        task?.cancel()
        task = nil
    }

    /// Cancels the pending retry and restores the full budget, once the reconciler has run.
    mutating func reset() {
        cancelPending()
        due = nil
        deferrals = 0
    }
}
