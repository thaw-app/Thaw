//
//  InventoryWalkPlanTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct InventoryWalkPlanTests {
    private let now = ContinuousClock.now

    @Test
    func `asks every app until a full walk has finished`() {
        let plan = InventoryWalkPlan.make(requested: [7], drawnOwners: [1, 2], lastFullWalk: nil, now: now)
        #expect(plan == InventoryWalkPlan(scope: .discovery, priorityOwners: [7]))
    }

    @Test
    func `asks only the apps that can have changed while a full walk is recent`() {
        let plan = InventoryWalkPlan.make(requested: [7], drawnOwners: [1, 2], lastFullWalk: now - .seconds(10), now: now)
        #expect(plan == InventoryWalkPlan(scope: .settledOwners, priorityOwners: [1, 2, 7]))
    }

    @Test
    func `falls back to every app when the bar could not be read`() {
        let plan = InventoryWalkPlan.make(requested: [], drawnOwners: nil, lastFullWalk: now - .seconds(10), now: now)
        #expect(plan.scope == .discovery)
    }

    @Test
    func `walks every app again once the last full walk is old`() {
        let stale = now - InventoryWalkPlan.fullWalkInterval
        let plan = InventoryWalkPlan.make(requested: [], drawnOwners: [1], lastFullWalk: stale, now: now)
        #expect(plan.scope == .discovery)
    }

    @Test
    func `the ledger remembers a finished full walk and forgets it on request`() {
        let ledger = FullWalkLedger()
        #expect(ledger.lastFullWalk == nil)
        ledger.noteFullWalk(at: now)
        #expect(ledger.lastFullWalk == now)
        ledger.forget()
        #expect(ledger.lastFullWalk == nil)
    }
}
