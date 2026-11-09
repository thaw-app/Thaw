//
//  MenuBarScanStateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("Budgeted menu bar discovery")
struct MenuBarScanStateTests {
    @Test("Repeated short scans reach every owner and always visit controls first")
    func truncatedScansMakeProgress() {
        var state = MenuBarScanState<String>()
        let owners = Array(Int32(1) ... 199)
        var visited = Set<Int32>()
        for _ in 0 ..< 3 {
            let pass = state.begin(owners: owners, priorityOwners: [198, 199])
            #expect(Array(pass.owners.prefix(2)) == [198, 199])
            for owner in pass.owners.prefix(100) {
                state.didAttempt(owner: owner, generation: pass.generation)
                state.record(["item-\(owner)"], owner: owner, generation: pass.generation)
                visited.insert(owner)
            }
        }
        #expect(visited == Set(owners))
        #expect(state.observations.count == 199)
    }

    @Test("A process that launched since the last scan is asked before the rotation")
    func newOwnerIsNotLeftBehindATruncatedScan() {
        var state = MenuBarScanState<String>()
        let owners = Array(Int32(1) ... 100)
        let first = state.begin(owners: owners, priorityOwners: [100])
        for owner in first.owners {
            state.didAttempt(owner: owner, generation: first.generation)
            state.record([], owner: owner, generation: first.generation)
        }
        let second = state.begin(owners: owners + [500], priorityOwners: [100])
        #expect(Array(second.owners.prefix(2)) == [100, 500])
    }

    /// 2026-11-06: four processes launched after the last full walk made every capture read fall
    /// back to a two-second walk of every app, though all 17 item owners had answered.
    @Test("An owner never read doesn't hold up the known owners, but a stale item owner does")
    func neverReadOwnersDontBlockKnownOwners() {
        var state = MenuBarScanState<String>()
        let full = state.begin(owners: [1, 2], priorityOwners: [])
        for owner in full.owners {
            state.didAttempt(owner: owner, generation: full.generation)
            state.record(owner == 1 ? ["item"] : [], owner: owner, generation: full.generation)
        }

        let targeted = state.begin(owners: [1, 2, 3], priorityOwners: [1], scope: .requestedOwners)
        state.didAttempt(owner: 1, generation: targeted.generation)
        state.record(["item"], owner: 1, generation: targeted.generation)

        #expect(!state.hasFreshKnownInventory(generation: targeted.generation), "the strict check still waits for 3")
        #expect(state.hasFreshItemOwners(generation: targeted.generation))

        let stale = state.begin(owners: [1, 2, 3], priorityOwners: [2], scope: .requestedOwners)
        state.didAttempt(owner: 2, generation: stale.generation)
        state.record([], owner: 2, generation: stale.generation)
        #expect(!state.hasFreshItemOwners(generation: stale.generation), "owner 1 has items and wasn't read again")
        #expect(state.hasFreshItemOwners(generation: stale.generation, excusing: [1]))
    }

    @Test("Background-only owners are asked after every other owner, but still asked")
    func backgroundOwnersGoLast() {
        var state = MenuBarScanState<String>()
        let pass = state.begin(owners: [1, 2, 3, 4, 5], priorityOwners: [5], deferredOwners: [2, 5])
        #expect(pass.owners == [5, 1, 3, 4, 2])
    }

    @Test("A walk that ran out of time before the background-only owners is still complete")
    func excusedBackgroundOwnersDoNotBlockCompleteness() {
        var state = MenuBarScanState<String>()
        let pass = state.begin(owners: [1, 2], priorityOwners: [], deferredOwners: [2])
        state.didAttempt(owner: 1, generation: pass.generation)
        state.record(["item"], owner: 1, generation: pass.generation)
        #expect(!state.isComplete(generation: pass.generation))
        #expect(!state.hasFreshKnownInventory(generation: pass.generation))
        // Owner 2 can't own an item, so leaving it unread proves nothing was missed.
        #expect(state.isComplete(pass, excusing: [2]))
        #expect(state.hasFreshKnownInventory(generation: pass.generation, excusing: [2]))
    }

    @Test("A background-only owner is excused only while Thaw holds no items for it")
    func deferredOwnerWithItemsIsNotExcused() {
        var state = MenuBarScanState<String>()
        // Owner 2 once showed an item; owner 3 answered empty; owner 4 was never read.
        let first = state.begin(owners: [1, 2, 3, 4], priorityOwners: [])
        for owner: Int32 in [1, 2, 3] {
            state.didAttempt(owner: owner, generation: first.generation)
        }
        state.record(["one"], owner: 1, generation: first.generation)
        state.record(["two"], owner: 2, generation: first.generation)
        state.record([], owner: 3, generation: first.generation)

        // A later walk reads owner 1 and runs out of time before the deferred owners.
        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], deferredOwners: [2, 3, 4])
        state.didAttempt(owner: 1, generation: pass.generation)
        state.record(["one"], owner: 1, generation: pass.generation)

        let excused = state.excusableDeferredOwners(of: pass)
        #expect(excused == [3, 4])
        // Owner 2's item wasn't read again, so its geometry is stale and the inventory isn't fresh.
        #expect(!state.hasFreshKnownInventory(generation: pass.generation, excusing: excused))
        #expect(!state.isComplete(pass, excusing: excused))

        // Once owner 2 answers empty it is excused like the others.
        let next = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], deferredOwners: [2, 3, 4])
        state.didAttempt(owner: 1, generation: next.generation)
        state.record(["one"], owner: 1, generation: next.generation)
        state.didAttempt(owner: 2, generation: next.generation)
        state.record([], owner: 2, generation: next.generation)
        let nextExcused = state.excusableDeferredOwners(of: next)
        #expect(nextExcused == [2, 3, 4])
        #expect(state.hasFreshKnownInventory(generation: next.generation, excusing: nextExcused))
    }

    @Test("An unvisited owner survives, but a successful empty answer removes its items")
    func absenceRequiresAnObservation() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        for owner in first.owners {
            state.didAttempt(owner: owner, generation: first.generation)
            state.record(["item-\(owner)"], owner: owner, generation: first.generation)
        }
        let second = state.begin(owners: [1, 2], priorityOwners: [])
        state.didAttempt(owner: 1, generation: second.generation)
        state.record([], owner: 1, generation: second.generation)
        #expect(state.observations == ["item-2"])
        #expect(state.freshObservations(generation: second.generation).isEmpty)
        #expect(!state.isComplete(generation: second.generation))
        _ = state.begin(owners: [1], priorityOwners: [])
        #expect(state.observations.isEmpty)
    }

    @Test("Reconciliation needs discovery coverage and fresh geometry for every known item")
    func reconciliationDoesNotWaitForEmptyOwnersEveryPass() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        state.didAttempt(owner: 1, generation: first.generation)
        state.record(["control"], owner: 1, generation: first.generation)
        #expect(!state.hasFreshKnownInventory(generation: first.generation))
        state.didAttempt(owner: 2, generation: first.generation)
        state.record([], owner: 2, generation: first.generation)

        let second = state.begin(owners: [1, 2], priorityOwners: [])
        #expect(!state.hasFreshKnownInventory(generation: second.generation))
        state.didAttempt(owner: 1, generation: second.generation)
        state.record(["control moved"], owner: 1, generation: second.generation)
        #expect(!state.isComplete(generation: second.generation))
        #expect(state.hasFreshKnownInventory(generation: second.generation))

        let third = state.begin(owners: [1, 2, 3], priorityOwners: [])
        #expect(!state.hasFreshKnownInventory(generation: third.generation))
    }

    @Test("A late pre-move answer cannot overwrite a newer observation")
    func staleAnswersAreRejected() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1], priorityOwners: [])
        state.didAttempt(owner: 1, generation: first.generation)
        let second = state.begin(owners: [1], priorityOwners: [])
        state.didAttempt(owner: 1, generation: second.generation)
        state.record(["new position"], owner: 1, generation: second.generation)
        state.record(["old position"], owner: 1, generation: first.generation)
        #expect(state.observations == ["new position"])
        #expect(state.isComplete(generation: second.generation))
    }
}
