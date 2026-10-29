//
//  VisibleOrderCompletionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Saved Visible order completed with live items")
struct VisibleOrderCompletionTests {
    private func item(_ bundleID: String, windowID: CGWindowID, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: "Item-0", instanceIndex: 0),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: "Item-0",
            isOnScreen: true
        )
    }

    @Test("A live item the saved order does not name is filled in where the bar has it")
    func newcomerIsFilledIn() {
        let a = item("com.example.a", windowID: 1, x: 100)
        let now = item("com.example.nowplaying", windowID: 2, x: 140)
        let b = item("com.example.b", windowID: 3, x: 180)
        let completed = VisibleOrderCompletion.completed(
            [b.uniqueIdentifier, a.uniqueIdentifier],
            liveItems: [a, now, b],
            controller: InertSectionController(),
            experimentalSystemItemHiding: false
        )
        #expect(completed == [b.uniqueIdentifier, a.uniqueIdentifier, now.uniqueIdentifier])
    }

    @Test("An order that already names every live item is returned as it was")
    func completeOrderIsUnchanged() {
        let a = item("com.example.a", windowID: 1, x: 100)
        let b = item("com.example.b", windowID: 2, x: 140)
        let order = [b.uniqueIdentifier, a.uniqueIdentifier]
        let completed = VisibleOrderCompletion.completed(
            order,
            liveItems: [a, b],
            controller: InertSectionController(),
            experimentalSystemItemHiding: false
        )
        #expect(completed == order)
    }

    @Test("Thaw's Visible control is named even though it is not eligible for section order")
    func visibleControlIsNamed() {
        let a = item("com.example.a", windowID: 1, x: 100)
        let control = MenuBarItem(
            tag: .visibleControlItem,
            windowID: 0xFFFF_FE01,
            ownerPID: 100,
            sourcePID: 100,
            bounds: CGRect(x: 140, y: 0, width: 24, height: 24),
            title: MenuBarItemTag.visibleControlItem.title,
            isOnScreen: true
        )
        let b = item("com.example.b", windowID: 3, x: 180)
        let completed = VisibleOrderCompletion.completed(
            [a.uniqueIdentifier, b.uniqueIdentifier],
            liveItems: [a, control, b],
            controller: InertSectionController(),
            experimentalSystemItemHiding: false
        )
        #expect(completed == [a.uniqueIdentifier, control.uniqueIdentifier, b.uniqueIdentifier])
    }
}
