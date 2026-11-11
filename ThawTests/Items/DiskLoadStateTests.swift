//
//  DiskLoadStateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Image cache disk load state")
struct DiskLoadStateTests {
    @Test("With no load in flight a save runs at once")
    func saveRunsWhenIdle() {
        var state = DiskLoadState()
        let held = state.holdsSave()
        #expect(!held)
        #expect(!state.isSaveOwed)
    }

    @Test("A save asked for while a load is in flight is held, and runs once when the load is done")
    func saveWaitsForLoad() {
        var state = DiskLoadState()
        state.began()
        let first = state.holdsSave()
        let second = state.holdsSave()
        #expect(first, "the file still holds pictures the load has not merged")
        #expect(second)

        let owed = state.finished()
        let heldAfter = state.holdsSave()
        let owedAgain = state.finished()
        #expect(owed, "the held save is owed now")
        #expect(!heldAfter)
        #expect(!owedAgain, "and only once")
    }

    @Test("A load nobody saved during owes nothing when it is done")
    func quietLoadOwesNothing() {
        var state = DiskLoadState()
        state.began()
        let owed = state.finished()
        #expect(!owed)
    }

    @Test("Emptying the cache on purpose refuses the load's result and drops the held save")
    func abandonedLoad() {
        var state = DiskLoadState()
        state.began()
        _ = state.holdsSave()
        let before = state.generation

        state.abandoned()
        let owed = state.finished()
        #expect(state.generation != before)
        #expect(!state.isInFlight)
        #expect(!owed, "nothing is left for the save to protect")
    }
}
