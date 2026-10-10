//
//  ItemOwnersMenuBarScanTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("A move reads only the apps that own items")
struct ItemOwnersMenuBarScanTests {
    /// Discovery has seen owners 1 to 4; 1 and 2 own items, 3 and 4 answered empty.
    private func discovered(at now: ContinuousClock.Instant) -> MenuBarScanState<String> {
        var state = MenuBarScanState<String>()
        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], now: now)
        for owner in pass.owners {
            state.didAttempt(owner: owner, generation: pass.generation)
            state.record(owner <= 2 ? ["item-\(owner)"] : [], owner: owner, generation: pass.generation, at: now)
        }
        return state
    }

    @Test("Apps that answered empty are skipped, however long ago they answered")
    func emptyOwnersAreSkipped() {
        let start = ContinuousClock.now
        var state = discovered(at: start)

        let move = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], scope: .itemOwners, now: start + .seconds(60))

        #expect(Set(move.owners) == [1, 2])
    }

    @Test("The wider known-owners read probes those same empty apps again after five seconds")
    func knownOwnersReprobesExpiredEmpties() {
        let start = ContinuousClock.now
        var state = discovered(at: start)

        let move = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], scope: .knownOwners, now: start + .seconds(60))

        #expect(Set(move.owners) == [1, 2, 3, 4])
    }

    @Test("An app named by the move is read even if it answered empty")
    func requestedEmptyOwnerIsRead() {
        let start = ContinuousClock.now
        var state = discovered(at: start)

        let move = state.begin(owners: [1, 2, 3, 4], priorityOwners: [4], scope: .itemOwners, now: start)

        #expect(Set(move.owners) == [1, 2, 4])
    }

    @Test("An app nobody has read yet leaves the inventory incomplete, so the caller falls back")
    func undiscoveredOwnerLeavesInventoryIncomplete() {
        let start = ContinuousClock.now
        var state = discovered(at: start)

        let move = state.begin(owners: [1, 2, 3, 4, 5], priorityOwners: [], scope: .itemOwners, now: start)
        for owner in move.owners {
            state.didAttempt(owner: owner, generation: move.generation)
            state.record(["item-\(owner)"], owner: owner, generation: move.generation, at: start)
        }

        #expect(!move.owners.contains(5))
        #expect(state.isComplete(move))
        #expect(!state.hasFreshKnownInventory(generation: move.generation))
    }
}
