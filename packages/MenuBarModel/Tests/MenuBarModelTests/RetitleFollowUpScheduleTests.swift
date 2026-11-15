//
//  RetitleFollowUpScheduleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

@Suite("A quiet bar is read again for an app that may rename its item, a bounded number of times")
struct RetitleFollowUpScheduleTests {
    private let clock = "com.example.clock"
    private let chat = "com.example.chat"

    /// A task that stays alive until it is cancelled, standing in for the follow-up's wait.
    private func waitingTask() -> Task<Void, Never> {
        Task { try? await Task.sleep(for: .seconds(3600)) }
    }

    /// Runs one follow-up to its read: the wait is claimed, runs out and fires.
    private func runFollowUp(_ schedule: inout RetitleFollowUpSchedule, candidates: Set<String>) -> Bool {
        guard schedule.claim(candidates: candidates) != nil else { return false }
        schedule.fired()
        return true
    }

    @Test("A read that leaves an app to compare asks for another after the delay")
    func claimsAFollowUp() {
        var schedule = RetitleFollowUpSchedule()
        #expect(schedule.claim(candidates: [clock]) == RetitleFollowUpSchedule.delay)
    }

    @Test("A read that leaves no app to compare asks for nothing")
    func nothingToCompare() {
        var schedule = RetitleFollowUpSchedule()
        #expect(schedule.claim(candidates: []) == nil)
    }

    @Test("An app whose title never changes stops causing reads")
    func stopsAfterTheBudget() {
        var schedule = RetitleFollowUpSchedule()
        for _ in 0 ..< RetitleFollowUpSchedule.followUpsPerOwner {
            #expect(runFollowUp(&schedule, candidates: [clock]))
        }
        #expect(!runFollowUp(&schedule, candidates: [clock]))
        #expect(schedule.claim(candidates: [clock]) == nil, "and stays stopped")
    }

    @Test("Reads that arrive before the wait runs out use up no follow-up")
    func replacedWaitsAreFree() {
        var schedule = RetitleFollowUpSchedule()
        for _ in 0 ..< 10 {
            #expect(schedule.claim(candidates: [clock]) != nil)
        }
        for _ in 0 ..< RetitleFollowUpSchedule.followUpsPerOwner {
            #expect(runFollowUp(&schedule, candidates: [clock]))
        }
        #expect(!runFollowUp(&schedule, candidates: [clock]))
    }

    @Test("An app seen later gets its own follow-ups, and a spent app rides along for free")
    func lateArrivalHasItsOwnBudget() {
        var schedule = RetitleFollowUpSchedule()
        for _ in 0 ..< RetitleFollowUpSchedule.followUpsPerOwner {
            #expect(runFollowUp(&schedule, candidates: [clock]))
        }
        for _ in 0 ..< RetitleFollowUpSchedule.followUpsPerOwner {
            #expect(runFollowUp(&schedule, candidates: [clock, chat]))
        }
        #expect(!runFollowUp(&schedule, candidates: [clock, chat]))
    }

    @Test("One follow-up counts for every app it is for")
    func followUpsAreShared() {
        var schedule = RetitleFollowUpSchedule()
        for _ in 0 ..< RetitleFollowUpSchedule.followUpsPerOwner {
            #expect(runFollowUp(&schedule, candidates: [clock, chat]))
        }
        #expect(schedule.claim(candidates: [clock]) == nil)
        #expect(schedule.claim(candidates: [chat]) == nil)
    }

    @Test("An app that left before the wait ran out keeps its follow-ups")
    func onlyAwaitedAppsPay() {
        var schedule = RetitleFollowUpSchedule()
        _ = schedule.claim(candidates: [clock, chat])
        for _ in 0 ..< RetitleFollowUpSchedule.followUpsPerOwner {
            #expect(runFollowUp(&schedule, candidates: [chat]))
        }
        #expect(schedule.claim(candidates: [chat]) == nil)
        #expect(schedule.claim(candidates: [clock]) != nil)
    }

    @Test("A new read cancels the wait it replaces")
    func newReadCancelsTheWait() {
        var schedule = RetitleFollowUpSchedule()
        let first = waitingTask()
        let second = waitingTask()
        defer { second.cancel() }
        _ = schedule.claim(candidates: [clock])
        schedule.arm(first)

        _ = schedule.claim(candidates: [clock])
        schedule.arm(second)

        #expect(first.isCancelled)
        #expect(!second.isCancelled)
    }

    @Test("A read with nothing left to compare cancels the wait")
    func emptyReadCancelsTheWait() {
        var schedule = RetitleFollowUpSchedule()
        let task = waitingTask()
        _ = schedule.claim(candidates: [clock])
        schedule.arm(task)

        #expect(schedule.claim(candidates: []) == nil)
        #expect(task.isCancelled)
    }

    @Test("The follow-up's own read does not cancel the task running it")
    func firedTaskSurvivesItsOwnRead() {
        var schedule = RetitleFollowUpSchedule()
        let task = waitingTask()
        defer { task.cancel() }
        _ = schedule.claim(candidates: [clock])
        schedule.arm(task)

        schedule.fired()
        _ = schedule.claim(candidates: [clock])

        #expect(!task.isCancelled)
    }
}
