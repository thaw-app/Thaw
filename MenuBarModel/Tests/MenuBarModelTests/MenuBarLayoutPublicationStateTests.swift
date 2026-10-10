//
//  MenuBarLayoutPublicationStateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

struct MenuBarLayoutPublicationStateTests {
    @Test("A scan started before or during a move cannot publish afterward")
    func movementInvalidatesScans() {
        var state = MenuBarLayoutPublicationState()
        let before = state.generation
        state.beginMutation()
        let during = state.generation
        #expect(!state.canPublish(generation: before))
        #expect(!state.canPublish(generation: during))
        state.endMutation()
        #expect(!state.canPublish(generation: before))
        #expect(!state.canPublish(generation: during))
        #expect(state.canPublish(generation: state.generation))
    }

    @Test("A nested transition retains its publication hold until the last release")
    func nestedMutation() {
        var state = MenuBarLayoutPublicationState()
        state.beginMutation()
        state.beginMutation()
        state.endMutation()
        #expect(!state.canPublish(generation: state.generation))
        state.endMutation()
        #expect(state.canPublish(generation: state.generation))
    }

    @Test("New authored intent invalidates an older scan without starting a move")
    func authoredEdit() {
        var state = MenuBarLayoutPublicationState()
        let before = state.generation
        state.invalidate()
        #expect(!state.canPublish(generation: before))
    }
}
