//
//  ControlItemAppearanceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
struct ControlItemAppearanceTests {
    @Test func synchronousToggleAndQueuedNotificationRenderOnlyOnce() {
        let updates = ControlItem.StateAppearanceUpdates()
        var renders = 0
        let render = { renders += 1; return true }

        updates.apply(state: .showSection, stateChangeOnly: false, render: render)
        updates.apply(state: .showSection, stateChangeOnly: true, render: render)
        #expect(renders == 1)

        updates.apply(state: .hideSection, stateChangeOnly: false, render: render)
        updates.apply(state: .hideSection, stateChangeOnly: true, render: render)
        #expect(renders == 2)
    }

    @Test func stateNotificationStillRendersWithoutSynchronousFlush() {
        let updates = ControlItem.StateAppearanceUpdates()
        var renders = 0
        let render = { renders += 1; return true }

        updates.apply(state: .hideSection, stateChangeOnly: true, render: render)
        updates.apply(state: .showSection, stateChangeOnly: true, render: render)
        #expect(renders == 2)
    }

    @Test func settingsRefreshRendersEvenWhenHidingStateHasNotChanged() {
        let updates = ControlItem.StateAppearanceUpdates()
        var renders = 0
        let render = { renders += 1; return true }

        updates.apply(state: .hideSection, stateChangeOnly: false, render: render)
        updates.apply(state: .hideSection, stateChangeOnly: false, render: render)
        #expect(renders == 2)
    }

    @Test func unavailableButtonDoesNotSuppressNextStateNotification() {
        let updates = ControlItem.StateAppearanceUpdates()
        #expect(!updates.apply(state: .showSection, stateChangeOnly: false, render: { false }))
        #expect(updates.apply(state: .showSection, stateChangeOnly: true, render: { true }))
    }
}
