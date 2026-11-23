//
//  MenuBarScanScopeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

/// Narrow reads that ask only some owners. Uses the MenuBarScanState helpers in MenuBarScanStateTests.swift.
@Suite("A move reads only the apps that own items")
struct MenuBarScanItemOwnersTests {
    @Test("Apps that answered empty are skipped, however long ago they answered")
    func emptyOwnersAreSkipped() {
        let start = ContinuousClock.now
        var state = MenuBarScanState<String>.discovered(at: start)
        let move = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], scope: .itemOwners, now: start + .seconds(60))
        #expect(Set(move.owners) == [1, 2])
    }

    @Test("An app named by the move is read even if it answered empty")
    func requestedEmptyOwnerIsRead() {
        let start = ContinuousClock.now
        var state = MenuBarScanState<String>.discovered(at: start)
        let move = state.begin(owners: [1, 2, 3, 4], priorityOwners: [4], scope: .itemOwners, now: start)
        #expect(Set(move.owners) == [1, 2, 4])
    }

    @Test("An app nobody has read yet leaves the inventory incomplete, so the caller falls back")
    func undiscoveredOwnerLeavesInventoryIncomplete() {
        let start = ContinuousClock.now
        var state = MenuBarScanState<String>.discovered(at: start)
        let move = state.begin(owners: [1, 2, 3, 4, 5], priorityOwners: [], scope: .itemOwners, now: start)
        state.answerAll(move, at: start)
        #expect(!move.owners.contains(5))
        #expect(state.isComplete(move))
        #expect(!state.hasFreshKnownInventory(generation: move.generation))
    }
}

@Suite("A settled read asks the apps that can have changed")
struct MenuBarScanSettledOwnersTests {
    @Test("Apps that answered empty are skipped")
    func emptyOwnersAreSkipped() {
        let start = ContinuousClock.now
        var state = MenuBarScanState<String>.discovered(at: start)
        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], scope: .settledOwners, now: start + .seconds(60))
        #expect(Set(pass.owners) == [1, 2])
    }

    @Test("An app drawn on the bar is asked even though it answered empty before")
    func drawnOwnersAreAsked() {
        let start = ContinuousClock.now
        var state = MenuBarScanState<String>.discovered(at: start)
        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [4], scope: .settledOwners, now: start + .seconds(1))
        #expect(Set(pass.owners) == [1, 2, 4])
    }

    @Test("An app launched since the full walk is asked once, then skipped if it has nothing")
    func newOwnersAreAskedOnce() {
        let start = ContinuousClock.now
        var state = MenuBarScanState<String>.discovered(at: start)
        let first = state.begin(owners: [1, 2, 3, 4, 5], priorityOwners: [], scope: .settledOwners, now: start + .seconds(1))
        #expect(Set(first.owners) == [1, 2, 5])
        state.answerAll(first) { $0 == 5 ? [] : ["item-\($0)"] }
        #expect(state.hasFreshKnownInventory(generation: first.generation))

        let second = state.begin(owners: [1, 2, 3, 4, 5], priorityOwners: [], scope: .settledOwners, now: start + .seconds(2))
        #expect(Set(second.owners) == [1, 2])
    }

    @Test("An item owner that stops answering leaves the read short of fresh")
    func unansweredItemOwnerIsNotFresh() {
        let start = ContinuousClock.now
        var state = MenuBarScanState<String>.discovered(at: start)
        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], scope: .settledOwners, now: start + .seconds(1))
        state.answer(1, ["item-1"], in: pass)
        #expect(!state.hasFreshKnownInventory(generation: pass.generation))
        #expect(state.observations.sorted() == ["item-1", "item-2"])
    }

    @Test("An item owner that answers empty loses its item")
    func departedItemIsDropped() {
        let start = ContinuousClock.now
        var state = MenuBarScanState<String>.discovered(at: start)
        let pass = state.begin(owners: [1, 2, 3, 4], priorityOwners: [], scope: .settledOwners, now: start + .seconds(1))
        state.answerAll(pass) { $0 == 1 ? [] : ["item-\($0)"] }
        #expect(state.observations == ["item-2"])
    }
}

@Suite("Requested-owner reads for capture and appearance")
struct MenuBarScanRequestedOwnersTests {
    @Test("A requested-owner read vouches for the bar only when it covers every known item owner", arguments: [
        (Set<Int32>([1, 2]), true),
        (Set<Int32>([1]), false),
    ])
    func missedItemOwnerRefusesTheRead(requested: Set<Int32>, isFresh: Bool) {
        var state = MenuBarScanState<String>()
        state.answerAll(state.begin(owners: [1, 2, 3], priorityOwners: [])) { $0 == 3 ? [] : ["item-\($0)"] }

        let capture = state.begin(owners: [1, 2, 3], priorityOwners: requested, scope: .requestedOwners)
        #expect(Set(capture.owners) == requested)
        state.answerAll(capture)
        #expect(state.isComplete(capture))
        #expect(state.hasFreshKnownInventory(generation: capture.generation) == isFresh)
    }

    @Test("An app launched since the last discovery refuses the read until it is probed")
    func unprobedAppRefusesTheRead() {
        var state = MenuBarScanState<String>()
        state.answer(1, ["item-1"], in: state.begin(owners: [1], priorityOwners: []))

        let capture = state.begin(owners: [1, 2], priorityOwners: [1], scope: .requestedOwners)
        state.answer(1, ["item-1"], in: capture)
        #expect(state.isComplete(capture))
        #expect(!state.hasFreshKnownInventory(generation: capture.generation))
    }

    @Test("Appearance reads only its cached owners, including on the first request")
    func coldReadDoesNotDiscoverUnrelatedApps() {
        var state = MenuBarScanState<String>()
        let pass = state.begin(owners: [1, 2, 3], priorityOwners: [1], scope: .requestedOwners)
        #expect(pass.owners == [1])
        state.answer(1, ["icon"], in: pass)
        #expect(state.isComplete(pass))
        #expect(!state.hasFreshKnownInventory(generation: pass.generation))
    }

    @Test("Expired empty apps and unrequested neighbours do not delay appearance")
    func idleReadDoesNotRestartDiscovery() {
        var state = MenuBarScanState<String>()
        let now = ContinuousClock.now
        state.answerAll(state.begin(owners: [1, 2, 3], priorityOwners: [], now: now), at: now) {
            $0 == 3 ? [] : ["icon-\($0)"]
        }
        let appearance = state.begin(
            owners: [1, 2, 3, 4],
            priorityOwners: [1],
            scope: .requestedOwners,
            now: now + .seconds(10)
        )
        #expect(appearance.owners == [1])
        state.answer(1, ["new frame"], in: appearance)
        #expect(state.freshObservations(generation: appearance.generation) == ["new frame"])
        // A focused read must not evict other owners.
        #expect(state.observations.contains("icon-2"))

        let nextDiscovery = state.begin(owners: [1, 2, 3, 4], priorityOwners: [])
        #expect(Set(nextDiscovery.owners) == [1, 2, 3, 4])
    }
}
