//
//  RetitleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
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

/// An item that reads with its identifier most of the time keeps that identity on a read that misses it.
@Suite("Retitle identity memory")
struct RetitleIdentityMemoryTests {
    private typealias Slot = RetitleIdentityMemory.Slot

    /// Raycast's calendar item is "calendar-events" with titles like "Standup • in 52m".
    @Test("A read that falls back to the title keeps the slot's last stable identity")
    func titleFallbackKeepsTheIdentity() {
        var memory = RetitleIdentityMemory()
        #expect(memory.resolve(owner: 7, slots: [Slot("calendar-events", isStable: true), Slot("clipboard", isStable: true)])
            == ["calendar-events", "clipboard"])
        #expect(memory.resolve(owner: 7, slots: [Slot("Standup • in 52m", isStable: false), Slot("clipboard", isStable: true)])
            == ["calendar-events", "clipboard"])
        #expect(memory.resolve(owner: 7, slots: [Slot("Standup • in 51m", isStable: false), Slot("clipboard", isStable: true)])
            == ["calendar-events", "clipboard"], "the kept identity carries over to the next fallback")
    }

    @Test("A different number of items, another process or no earlier stable read leaves titles alone")
    func refusesWhenTheSlotsDontLineUp() {
        var memory = RetitleIdentityMemory()
        _ = memory.resolve(owner: 7, slots: [Slot("calendar-events", isStable: true)])
        #expect(memory.resolve(owner: 7, slots: [Slot("Standup", isStable: false), Slot("new", isStable: true)]) == ["Standup", "new"])
        #expect(memory.resolve(owner: 8, slots: [Slot("Standup", isStable: false)]) == ["Standup"])

        var fresh = RetitleIdentityMemory()
        _ = fresh.resolve(owner: 7, slots: [Slot("Standup", isStable: false)])
        #expect(fresh.resolve(owner: 7, slots: [Slot("Review", isStable: false)]) == ["Review"])
    }

    @Test("A process identifier handed to another app does not inherit the old app's identity")
    func reusedProcessIdentifier() {
        var memory = RetitleIdentityMemory()
        _ = memory.resolve(owner: 7, app: "com.example.calendar", slots: [Slot("calendar-events", isStable: true)])
        #expect(memory.resolve(owner: 7, app: "com.example.other", slots: [Slot("Status", isStable: false)]) == ["Status"])
        #expect(memory.resolve(owner: 7, app: "com.example.calendar", slots: [Slot("Standup", isStable: false)]) == ["Standup"],
                "the other app's read replaced the memory")

        _ = memory.resolve(owner: 8, app: "com.example.calendar", slots: [Slot("calendar-events", isStable: true)])
        #expect(memory.resolve(owner: 8, app: "com.example.calendar", slots: [Slot("Standup", isStable: false)]) == ["calendar-events"])
    }

    @Test("An identity another slot already has is not given out twice")
    func noDuplicateIdentities() {
        var memory = RetitleIdentityMemory()
        _ = memory.resolve(owner: 7, slots: [Slot("a", isStable: true), Slot("b", isStable: true)])
        #expect(memory.resolve(owner: 7, slots: [Slot("b", isStable: true), Slot("Title", isStable: false)]) == ["b", "Title"])
    }

    @Test("The memory keeps a bounded number of processes, dropping the oldest")
    func boundedByOwner() {
        var memory = RetitleIdentityMemory(capacity: 2)
        _ = memory.resolve(owner: 1, slots: [Slot("one", isStable: true)])
        _ = memory.resolve(owner: 2, slots: [Slot("two", isStable: true)])
        _ = memory.resolve(owner: 3, slots: [Slot("three", isStable: true)])
        #expect(memory.resolve(owner: 1, slots: [Slot("Title", isStable: false)]) == ["Title"])
        #expect(memory.resolve(owner: 3, slots: [Slot("Title", isStable: false)]) == ["three"])
    }

    @Test("An app read on every pass keeps its memory when others come and go")
    func dropsTheLeastRecentlyRead() {
        var memory = RetitleIdentityMemory(capacity: 2)
        _ = memory.resolve(owner: 1, slots: [Slot("one", isStable: true)])
        _ = memory.resolve(owner: 2, slots: [Slot("two", isStable: true)])
        _ = memory.resolve(owner: 1, slots: [Slot("one", isStable: true)])
        _ = memory.resolve(owner: 3, slots: [Slot("three", isStable: true)])
        #expect(memory.resolve(owner: 1, slots: [Slot("Title", isStable: false)]) == ["one"])
        #expect(memory.resolve(owner: 2, slots: [Slot("Title", isStable: false)]) == ["Title"])
    }
}
