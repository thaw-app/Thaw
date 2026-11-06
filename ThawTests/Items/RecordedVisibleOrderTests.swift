//
//  RecordedVisibleOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct RecordedVisibleOrderTests {
    @Test("A native rearrangement takes precedence over the controller's launch order")
    func mirroredOrderWins() {
        let launchOrder = ["A", "B", "Thaw"]
        let draggedOrder = ["Thaw", "B", "A"]
        #expect(
            ControlOrderRules.freshestRecordedVisibleOrder(
                mirroredOrder: draggedOrder,
                controllerOrder: launchOrder
            ) == draggedOrder
        )
    }

    @Test("The controller supplies the order before the first cache snapshot")
    func controllerOrderIsFallback() {
        #expect(
            ControlOrderRules.freshestRecordedVisibleOrder(
                mirroredOrder: nil,
                controllerOrder: ["A", "Thaw"]
            ) == ["A", "Thaw"]
        )
        #expect(
            ControlOrderRules.freshestRecordedVisibleOrder(
                mirroredOrder: nil,
                controllerOrder: nil
            ).isEmpty
        )
    }

    @Test("An explicitly empty mirror does not revive stale entries")
    func emptyMirrorWins() {
        #expect(
            ControlOrderRules.freshestRecordedVisibleOrder(
                mirroredOrder: [],
                controllerOrder: ["A", "Thaw"]
            ).isEmpty
        )
    }

    @Test("A drag newer than the mirror leaves the order to the bar")
    func dragNewerThanTheMirrorLeavesTheOrderToTheBar() {
        #expect(
            ControlOrderRules.freshestRecordedVisibleOrder(
                mirroredOrder: ["A", "Thaw"],
                controllerOrder: ["Thaw", "A"],
                userDraggedSinceMirror: true
            ).isEmpty
        )
        #expect(
            ControlOrderRules.freshestRecordedVisibleOrder(
                mirroredOrder: ["A", "Thaw"],
                controllerOrder: ["Thaw", "A"],
                userDraggedSinceMirror: false
            ) == ["A", "Thaw"]
        )
    }

    @Test("The structural pass after a drag keeps the drop")
    func structuralPassAfterADragKeepsTheDrop() {
        func app(_ name: String, x: CGFloat) -> MenuBarItem {
            item(MenuBarItemTag(namespace: .string("com.example.\(name)"), title: "Item"), x: x)
        }
        let apps = zip(
            ["droppy", "cyberark", "floe", "crashplan", "okta", "cortex", "netskope", "jamf", "shottr"],
            [1152, 1190, 1230, 1260, 1292, 1332, 1370, 1446, 1565] as [CGFloat]
        ).map { app($0, x: $1) }
        let thaw = item(.visibleControlItem, x: 1595)
        let controlCenter = item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 1637)
        let clock = item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 1676)
        let launchOrder = (apps.prefix(2) + [thaw] + apps.dropFirst(2) + [controlCenter, clock]).map(\.uniqueIdentifier)
        let barOrder = (apps + [thaw, controlCenter, clock]).map(\.uniqueIdentifier)

        func segment(draggedSinceMirror: Bool) -> [String] {
            let saved = ControlOrderRules.freshestRecordedVisibleOrder(
                mirroredOrder: launchOrder,
                controllerOrder: nil,
                userDraggedSinceMirror: draggedSinceMirror
            )
            return ControlOrderRules.structuralVisibleSegment(
                ordinaryVisibleItems: apps + [controlCenter, clock],
                visibleControl: thaw,
                savedOrder: saved
            ).map(\.uniqueIdentifier)
        }

        #expect(segment(draggedSinceMirror: true) == barOrder)
        #expect(segment(draggedSinceMirror: false) == launchOrder)
    }

    private func item(_ tag: MenuBarItemTag, x: CGFloat) -> MenuBarItem {
        MenuBarItem(tag: tag, windowID: 1, ownerPID: 1, sourcePID: 1,
                    bounds: CGRect(x: x, y: 3, width: 20, height: 24),
                    title: tag.title, isOnScreen: true)
    }
}
