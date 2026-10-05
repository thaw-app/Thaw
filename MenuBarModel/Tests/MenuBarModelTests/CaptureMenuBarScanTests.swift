//
//  CaptureMenuBarScanTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

struct CaptureMenuBarScanTests {
    @Test("A requested-owner read vouches for the bar only when it covers every known item owner", arguments: [
        (Set<Int32>([1, 2]), true),
        (Set<Int32>([1]), false),
    ])
    func missedItemOwnerRefusesTheRead(requested: Set<Int32>, isFresh: Bool) {
        var state = MenuBarScanState<String>()
        let discovery = state.begin(owners: [1, 2, 3], priorityOwners: [])
        for owner in discovery.owners {
            state.didAttempt(owner: owner, generation: discovery.generation)
            state.record(owner == 3 ? [] : ["icon-\(owner)"], owner: owner, generation: discovery.generation)
        }

        let capture = state.begin(owners: [1, 2, 3], priorityOwners: requested, scope: .requestedOwners)
        #expect(Set(capture.owners) == requested)
        for owner in capture.owners {
            state.didAttempt(owner: owner, generation: capture.generation)
            state.record(["icon-\(owner)"], owner: owner, generation: capture.generation)
        }
        #expect(state.isComplete(capture))
        #expect(state.hasFreshKnownInventory(generation: capture.generation) == isFresh)
    }

    @Test("An app launched since the last discovery refuses the read until it is probed")
    func unprobedAppRefusesTheRead() {
        var state = MenuBarScanState<String>()
        let discovery = state.begin(owners: [1], priorityOwners: [])
        state.didAttempt(owner: 1, generation: discovery.generation)
        state.record(["icon-1"], owner: 1, generation: discovery.generation)

        let capture = state.begin(owners: [1, 2], priorityOwners: [1], scope: .requestedOwners)
        state.didAttempt(owner: 1, generation: capture.generation)
        state.record(["icon-1"], owner: 1, generation: capture.generation)
        #expect(state.isComplete(capture))
        #expect(!state.hasFreshKnownInventory(generation: capture.generation))
    }
}
