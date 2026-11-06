//
//  SettledOwnersMenuBarScanTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("A settled read asks the apps that can have changed")
struct SettledOwnersMenuBarScanTests {
    /// A full walk has seen owners 1 to 4; 1 and 2 own items, 3 and 4 answered empty.
    private func discovered(at now: ContinuousClock.Instant) -> MenuBarScanState<String> {
        var state = MenuBarScanState<String>()
        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], now: now)
        for owner in pass.owners {
            state.didAttempt(owner: owner, generation: pass.generation)
            state.record(owner <= 2 ? ["item-\(owner)"] : [], owner: owner, generation: pass.generation, at: now)
        }
        return state
    }

    @Test("Apps that answered empty are skipped")
    func emptyOwnersAreSkipped() {
        let start = ContinuousClock.now
        var state = discovered(at: start)

        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], scope: .settledOwners, now: start + .seconds(60))

        #expect(Set(pass.owners) == [1, 2])
    }

    @Test("An app drawn on the bar is asked even though it answered empty before")
    func drawnOwnersAreAsked() {
        let start = ContinuousClock.now
        var state = discovered(at: start)

        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [4], scope: .settledOwners, now: start + .seconds(1))

        #expect(Set(pass.owners) == [1, 2, 4])
    }

    @Test("An app launched since the full walk is asked once, then skipped if it has nothing")
    func newOwnersAreAskedOnce() {
        let start = ContinuousClock.now
        var state = discovered(at: start)

        let first = state.begin(owners: [1, 2, 3, 4, 5], priorityOwners: [], scope: .settledOwners, now: start + .seconds(1))
        #expect(Set(first.owners) == [1, 2, 5])
        for owner in first.owners {
            state.didAttempt(owner: owner, generation: first.generation)
            state.record(owner == 5 ? [] : ["item-\(owner)"], owner: owner, generation: first.generation)
        }
        #expect(state.hasFreshKnownInventory(generation: first.generation))

        let second = state.begin(owners: [1, 2, 3, 4, 5], priorityOwners: [], scope: .settledOwners, now: start + .seconds(2))
        #expect(Set(second.owners) == [1, 2])
    }

    @Test("An item owner that stops answering leaves the read short of fresh")
    func unansweredItemOwnerIsNotFresh() {
        let start = ContinuousClock.now
        var state = discovered(at: start)

        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], scope: .settledOwners, now: start + .seconds(1))
        state.didAttempt(owner: 1, generation: pass.generation)
        state.record(["item-1"], owner: 1, generation: pass.generation)

        #expect(!state.hasFreshKnownInventory(generation: pass.generation))
        #expect(state.observations.sorted() == ["item-1", "item-2"])
    }

    @Test("An item owner that answers empty loses its item")
    func departedItemIsDropped() {
        let start = ContinuousClock.now
        var state = discovered(at: start)

        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], scope: .settledOwners, now: start + .seconds(1))
        for owner in pass.owners {
            state.didAttempt(owner: owner, generation: pass.generation)
            state.record(owner == 1 ? [] : ["item-\(owner)"], owner: owner, generation: pass.generation)
        }

        #expect(state.observations == ["item-2"])
    }
}
