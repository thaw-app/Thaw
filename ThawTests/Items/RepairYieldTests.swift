//
//  RepairYieldTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("An automatic pass can tell when the user is waiting behind it")
struct RepairYieldTests {
    @Test("Nobody is waiting on a lane with one holder")
    func nobodyWaiting() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.postRestrictionRepair))

        #expect(!repairs.userWorkIsWaiting)
        repairs.leave(holder)
    }

    @Test("A queued automatic pass does not count as the user waiting")
    func automaticWaiterDoesNotCount() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.postRestrictionRepair))
        let queued = Task { await repairs.enter(.overflowRebalance) }
        try await Task.sleep(for: .milliseconds(50))

        #expect(!repairs.userWorkIsWaiting)

        repairs.leave(holder)
        let next = try #require(await queued.value)
        repairs.leave(next)
    }

    @Test("A queued user edit counts, until it is admitted")
    func userWaiterCounts() async throws {
        let repairs = RepairOrchestrator()
        let holder = try #require(await repairs.enter(.postRestrictionRepair))
        let queued = Task { await repairs.enterForUserEdit() }
        try await Task.sleep(for: .milliseconds(50))

        #expect(repairs.userWorkIsWaiting)

        repairs.leave(holder)
        let next = try #require(await queued.value)
        #expect(!repairs.userWorkIsWaiting)
        repairs.leave(next)
    }
}
