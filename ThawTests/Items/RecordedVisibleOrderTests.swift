//
//  RecordedVisibleOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
struct RecordedVisibleOrderTests {
    @Test("A native rearrangement takes precedence over the controller's launch order")
    func mirroredOrderWins() {
        let launchOrder = ["A", "B", "Thaw"]
        let draggedOrder = ["Thaw", "B", "A"]
        #expect(
            MenuBarItemManager.freshestRecordedVisibleOrder(
                mirroredOrder: draggedOrder,
                controllerOrder: launchOrder
            ) == draggedOrder
        )
    }

    @Test("The controller supplies the order before the first cache snapshot")
    func controllerOrderIsFallback() {
        #expect(
            MenuBarItemManager.freshestRecordedVisibleOrder(
                mirroredOrder: nil,
                controllerOrder: ["A", "Thaw"]
            ) == ["A", "Thaw"]
        )
        #expect(
            MenuBarItemManager.freshestRecordedVisibleOrder(
                mirroredOrder: nil,
                controllerOrder: nil
            ).isEmpty
        )
    }

    @Test("An explicitly empty mirror does not revive stale entries")
    func emptyMirrorWins() {
        #expect(
            MenuBarItemManager.freshestRecordedVisibleOrder(
                mirroredOrder: [],
                controllerOrder: ["A", "Thaw"]
            ).isEmpty
        )
    }
}
