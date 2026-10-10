//
//  TrailingSiriLayoutTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct TrailingSiriLayoutTests {
    private func item(_ tag: MenuBarItemTag, x: CGFloat, onScreen: Bool = true) -> MenuBarItem {
        MenuBarItem(tag: tag, windowID: 1, ownerPID: 1, sourcePID: 1,
                    bounds: CGRect(x: x, y: 3, width: 20, height: 24),
                    title: tag.title, isOnScreen: onScreen)
    }

    @Test(arguments: [false, true])
    func structuralPlanRejectsSavedSiriInterleaving(hasSavedOrder: Bool) {
        let app = item(MenuBarItemTag(namespace: .string("com.example.app"), title: "Item"), x: 100)
        let siri = item(.siri, x: 130)
        let visible = item(.visibleControlItem, x: 160)
        let cc = item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 190)
        let clock = item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 220)
        let saved = hasSavedOrder ? [siri, app, visible, cc, clock].map(\.uniqueIdentifier) : []

        let plan = MenuBarItemManager.structuralVisibleSegment(
            ordinaryVisibleItems: [app, siri, cc, clock],
            visibleControl: visible,
            savedOrder: saved
        )

        #expect(plan.map(\.uniqueIdentifier) == [app, visible, siri, cc, clock].map(\.uniqueIdentifier))
    }

    @Test
    func ambientRepairDetectsSiriBeforeTheVisibleControl() {
        let siri = item(.siri, x: 100)
        let visible = item(.visibleControlItem, x: 130)
        let cc = item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 160)
        #expect(MenuBarItemManager.trailingSiriIsMisplaced(in: [siri, visible, cc]))
        #expect(MenuBarItemManager.trailingSiriIsMisplaced(in: [item(.siri, x: 150), visible, cc]) == false)
        #expect(MenuBarItemManager.trailingSiriIsMisplaced(in: [siri, item(.visibleControlItem, x: 130, onScreen: false), cc]) == false)
        #expect(MenuBarItemManager.trailingSiriIsMisplaced(in: [visible, cc]) == false)
    }

    @Test
    func validationDetectsSiriBeforeAnOrdinaryApp() {
        let siri = item(.siri, x: 100)
        let app = item(MenuBarItemTag(namespace: .string("com.example.app"), title: "Item"), x: 130)
        let cc = item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 160)
        let clock = item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 190)
        #expect(MenuBarItemManager.anchoredTrailingViolation(in: [siri, app, cc, clock]) != nil)
        #expect(MenuBarItemManager.anchoredTrailingViolation(in: [app, siri, cc, clock]) == nil)
    }

    @Test
    func validationIgnoresConcealedFramesRightOfTheClock() {
        let cc = item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 160)
        let clock = item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 190)
        let parked = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.hidden"), title: "Item"),
            windowID: 2,
            ownerPID: 2,
            sourcePID: 2,
            bounds: CGRect(x: 300, y: 1140, width: 38, height: 24),
            title: "Item",
            isOnScreen: true
        )
        let onBar = item(MenuBarItemTag(namespace: .string("com.example.app"), title: "Item"), x: 300)
        #expect(MenuBarItemManager.anchoredTrailingViolation(in: [cc, clock, parked]) == nil)
        #expect(MenuBarItemManager.anchoredTrailingViolation(in: [cc, clock, onBar]) != nil)
    }
}
