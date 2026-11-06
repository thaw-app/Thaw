//
//  TargetedMenuBarScanTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

struct TargetedMenuBarScanTests {
    @Test("Cold and newly running owners are discovered, terminated owners are removed")
    func processChangesUpdateCoverage() {
        var state = MenuBarScanState<String>()
        let cold = state.begin(owners: [1, 2], priorityOwners: [], scope: .knownOwners)
        #expect(Set(cold.owners) == [1, 2])
        for owner in cold.owners {
            state.didAttempt(owner: owner, generation: cold.generation)
            state.record(["item-\(owner)"], owner: owner, generation: cold.generation)
        }
        let changed = state.begin(owners: [2, 3], priorityOwners: [1], scope: .knownOwners)
        #expect(Set(changed.owners) == [2, 3])
        #expect(state.observations == ["item-2"])
        state.record(["departed late answer"], owner: 1, generation: cold.generation)
        #expect(state.observations == ["item-2"])
    }

    @Test("A missing neighbour or late pre-write answer cannot complete move geometry")
    func incompleteGeometryCannotVerify() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        for owner in first.owners {
            state.didAttempt(owner: owner, generation: first.generation)
            state.record(["old-\(owner)"], owner: owner, generation: first.generation)
        }
        let move = state.begin(owners: [1, 2], priorityOwners: [1], scope: .knownOwners)
        for owner in move.owners {
            state.didAttempt(owner: owner, generation: move.generation)
        }
        state.record(["source"], owner: 1, generation: move.generation)
        state.record(["stale neighbour"], owner: 2, generation: first.generation)
        #expect(!state.isComplete(move))
        #expect(!state.hasFreshKnownInventory(generation: move.generation))
        #expect(state.freshObservations(generation: move.generation) == ["source"])
        state.record(["fresh neighbour"], owner: 2, generation: move.generation)
        #expect(state.isComplete(move))
        #expect(state.freshObservations(generation: move.generation) == ["source", "fresh neighbour"])
    }

    @Test("An excused slow neighbour completes move geometry without contributing stale items")
    func excusedNeighbourCompletesGeometry() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        for owner in first.owners {
            state.didAttempt(owner: owner, generation: first.generation)
            state.record(["old-\(owner)"], owner: owner, generation: first.generation)
        }
        let move = state.begin(owners: [1, 2], priorityOwners: [1], scope: .knownOwners)
        state.didAttempt(owner: 1, generation: move.generation)
        state.record(["source"], owner: 1, generation: move.generation)
        #expect(!state.isComplete(move))
        #expect(state.isComplete(move, excusing: [2]))
        #expect(state.hasFreshKnownInventory(generation: move.generation, excusing: [2]))
        #expect(!state.isComplete(move, excusing: [3]))
        #expect(state.freshObservations(generation: move.generation) == ["source"])
    }

    @Test("Previously empty owners are rediscovered after five seconds")
    func emptyOwnerKnowledgeExpires() {
        var state = MenuBarScanState<String>()
        let start = ContinuousClock.now
        let discovery = state.begin(owners: [1, 2], priorityOwners: [], now: start)
        for owner in discovery.owners {
            state.didAttempt(owner: owner, generation: discovery.generation)
            state.record(owner == 1 ? ["item"] : [], owner: owner, generation: discovery.generation, at: start)
        }
        let recent = state.begin(owners: [1, 2], priorityOwners: [], scope: .knownOwners, now: start + .seconds(1))
        #expect(recent.owners == [1])
        let expired = state.begin(owners: [1, 2], priorityOwners: [], scope: .knownOwners, now: start + .seconds(5))
        #expect(Set(expired.owners) == [1, 2])
    }

    @Test("A requested empty owner must answer again before a move can be verified")
    func priorityOwnerCannotUseAnOldEmptyAnswer() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        for owner in first.owners {
            state.didAttempt(owner: owner, generation: first.generation)
            state.record(owner == 1 ? ["source"] : [], owner: owner, generation: first.generation)
        }
        let move = state.begin(owners: [1, 2], priorityOwners: [2], scope: .knownOwners)
        for owner in move.owners {
            state.didAttempt(owner: owner, generation: move.generation)
        }
        state.record(["fresh source"], owner: 1, generation: move.generation)
        #expect(state.hasFreshKnownInventory(generation: move.generation))
        #expect(!state.isComplete(move))
        state.record([], owner: 2, generation: move.generation)
        #expect(state.isComplete(move))
    }

    @Test("An unresolved probe invalidates an older empty answer")
    func timedOutEmptyOwnerIsRetried() {
        var state = MenuBarScanState<String>()
        let discovery = state.begin(owners: [1], priorityOwners: [])
        state.didAttempt(owner: 1, generation: discovery.generation)
        state.record([], owner: 1, generation: discovery.generation)
        let pending = state.begin(owners: [1], priorityOwners: [])
        state.didAttempt(owner: 1, generation: pending.generation)
        let move = state.begin(owners: [1], priorityOwners: [], scope: .knownOwners)
        #expect(move.owners == [1])
    }

    @Test("Move scans retain neighbour coverage without probing 122 empty applications")
    func knownOwnersIncludeNeighbours() {
        var state = MenuBarScanState<String>()
        let owners = Array(Int32(1) ... 126)
        let discovery = state.begin(owners: owners, priorityOwners: [])
        for owner in discovery.owners {
            state.didAttempt(owner: owner, generation: discovery.generation)
            state.record(owner <= 3 ? ["item-\(owner)"] : [], owner: owner, generation: discovery.generation)
        }
        let move = state.begin(owners: owners, priorityOwners: [1, 2, 126], scope: .knownOwners)
        #expect(Set(move.owners) == [1, 2, 3, 126])
        for owner in move.owners {
            state.didAttempt(owner: owner, generation: move.generation)
            state.record(["fresh-\(owner)"], owner: owner, generation: move.generation)
        }
        #expect(state.hasFreshKnownInventory(generation: move.generation))
        #expect(state.freshObservations(generation: move.generation).contains("fresh-3"))
    }
}
