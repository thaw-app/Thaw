//
//  DeferredLayoutReconcileScheduleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("A blocked layout reconcile is retried once its blocking window ends, a bounded number of times")
struct DeferredLayoutReconcileScheduleTests {
    private let start = ContinuousClock.now

    /// A task that stays alive until it is cancelled, standing in for the retry's wait.
    private func waitingTask() -> Task<Void, Never> {
        Task { try? await Task.sleep(for: .seconds(3600)) }
    }

    @Test("The first claim is due after the delay and counts as one deferral")
    func firstClaim() {
        var schedule = DeferredLayoutReconcileSchedule()

        let due = schedule.claim(after: .seconds(5), now: start)

        #expect(due == start + .seconds(5))
        #expect(schedule.deferrals == 1)
        #expect(!schedule.isPending)
    }

    @Test("A later claim keeps the earlier pending retry and is not counted")
    func laterClaimKeepsThePendingRetry() {
        var schedule = DeferredLayoutReconcileSchedule()
        let task = waitingTask()
        defer { task.cancel() }
        _ = schedule.claim(after: .seconds(5), now: start)
        schedule.arm(task)

        let later = schedule.claim(after: .seconds(10), now: start)
        let same = schedule.claim(after: .seconds(5), now: start)

        #expect(later == nil)
        #expect(same == nil)
        #expect(schedule.deferrals == 1)
        #expect(schedule.isPending)
        #expect(!task.isCancelled)
    }

    @Test("An earlier claim replaces the pending retry and cancels it")
    func earlierClaimReplacesThePendingRetry() {
        var schedule = DeferredLayoutReconcileSchedule()
        let task = waitingTask()
        _ = schedule.claim(after: .seconds(10), now: start)
        schedule.arm(task)

        let earlier = schedule.claim(after: .seconds(5), now: start)

        #expect(earlier == start + .seconds(5))
        #expect(task.isCancelled)
        #expect(schedule.deferrals == 2)
        #expect(!schedule.isPending)
    }

    @Test("Claims stop at the limit")
    func claimsStopAtTheLimit() {
        var schedule = DeferredLayoutReconcileSchedule()
        for round in 0 ..< DeferredLayoutReconcileSchedule.limit {
            let due = schedule.claim(after: .seconds(5), now: start + .seconds(round))
            #expect(due != nil)
            schedule.fired()
        }

        let overLimit = schedule.claim(after: .seconds(5), now: start + .seconds(60))

        #expect(overLimit == nil)
        #expect(schedule.deferrals == DeferredLayoutReconcileSchedule.limit)
        #expect(DeferredLayoutReconcileSchedule.limit == 5)
    }

    @Test("A retry that fired leaves the count and lets a later claim through")
    func firedKeepsTheCount() {
        var schedule = DeferredLayoutReconcileSchedule()
        let task = waitingTask()
        defer { task.cancel() }
        _ = schedule.claim(after: .seconds(5), now: start)
        schedule.arm(task)

        schedule.fired()
        let next = schedule.claim(after: .seconds(10), now: start)

        #expect(!task.isCancelled)
        #expect(next == start + .seconds(10))
        #expect(schedule.deferrals == 2)
    }

    @Test("Cancelling the pending retry keeps the count, and a later claim is then accepted")
    func cancelPendingKeepsTheCount() {
        var schedule = DeferredLayoutReconcileSchedule()
        let task = waitingTask()
        _ = schedule.claim(after: .seconds(5), now: start)
        schedule.arm(task)

        schedule.cancelPending()

        #expect(task.isCancelled)
        #expect(!schedule.isPending)
        #expect(schedule.deferrals == 1)
        let later = schedule.claim(after: .seconds(10), now: start)
        #expect(later == start + .seconds(10))
        #expect(schedule.deferrals == 2)
    }

    @Test("A reset cancels the pending retry and restores the full budget")
    func resetRestoresTheBudget() {
        var schedule = DeferredLayoutReconcileSchedule()
        for _ in 0 ..< DeferredLayoutReconcileSchedule.limit {
            _ = schedule.claim(after: .seconds(5), now: start)
            schedule.fired()
        }
        let task = waitingTask()
        schedule.arm(task)

        schedule.reset()

        #expect(task.isCancelled)
        #expect(!schedule.isPending)
        #expect(schedule.deferrals == 0)
        let due = schedule.claim(after: .seconds(5), now: start)
        #expect(due == start + .seconds(5))
    }

    @Test("A custom limit is honoured")
    func customLimit() {
        var schedule = DeferredLayoutReconcileSchedule()

        let first = schedule.claim(after: .seconds(1), limit: 1, now: start)
        schedule.fired()
        let second = schedule.claim(after: .seconds(1), limit: 1, now: start)

        #expect(first != nil)
        #expect(second == nil)
    }
}
