//
//  AppearanceMenuBarScanTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

struct AppearanceMenuBarScanTests {
    @Test("Appearance reads only its cached owners, including on the first request")
    func coldReadDoesNotDiscoverUnrelatedApps() {
        var state = MenuBarScanState<String>()
        let pass = state.begin(owners: [1, 2, 3], priorityOwners: [1], scope: .requestedOwners)
        #expect(pass.owners == [1])
        state.didAttempt(owner: 1, generation: pass.generation)
        state.record(["icon"], owner: 1, generation: pass.generation)
        #expect(state.isComplete(pass))
        #expect(!state.hasFreshKnownInventory(generation: pass.generation))
    }

    @Test("Expired empty apps and unrequested neighbours do not delay appearance")
    func idleReadDoesNotRestartDiscovery() {
        var state = MenuBarScanState<String>()
        let now = ContinuousClock.now
        let discovery = state.begin(owners: [1, 2, 3], priorityOwners: [], now: now)
        for owner in discovery.owners {
            state.didAttempt(owner: owner, generation: discovery.generation)
            state.record(owner == 3 ? [] : ["icon-\(owner)"], owner: owner, generation: discovery.generation, at: now)
        }
        let appearance = state.begin(
            owners: [1, 2, 3, 4],
            priorityOwners: [1],
            scope: .requestedOwners,
            now: now + .seconds(10)
        )
        #expect(appearance.owners == [1])
        state.didAttempt(owner: 1, generation: appearance.generation)
        state.record(["new frame"], owner: 1, generation: appearance.generation)
        #expect(state.freshObservations(generation: appearance.generation) == ["new frame"])
        #expect(state.observations.contains("icon-2"), "A focused read must not evict other owners")

        let nextDiscovery = state.begin(owners: [1, 2, 3, 4], priorityOwners: [])
        #expect(Set(nextDiscovery.owners) == [1, 2, 3, 4])
    }
}
