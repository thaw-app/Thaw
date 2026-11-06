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

    @Test
    func structuralPlanKeepsASavedSiriSlot() {
        let app = item(MenuBarItemTag(namespace: .string("com.example.app"), title: "Item"), x: 100)
        let siri = item(.siri, x: 130)
        let visible = item(.visibleControlItem, x: 160)
        let cc = item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 190)
        let clock = item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 220)
        let saved = [siri, app, visible, cc, clock].map(\.uniqueIdentifier)

        let plan = ControlOrderRules.structuralVisibleSegment(
            ordinaryVisibleItems: [app, siri, cc, clock],
            visibleControl: visible,
            savedOrder: saved
        )

        #expect(plan.map(\.uniqueIdentifier) == [siri, app, visible, cc, clock].map(\.uniqueIdentifier))
    }

    @Test
    func structuralPlanKeepsAnUnsavedSiriWhereItSits() {
        let app = item(MenuBarItemTag(namespace: .string("com.example.app"), title: "Item"), x: 100)
        let siri = item(.siri, x: 130)
        let visible = item(.visibleControlItem, x: 160)
        let cc = item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 190)
        let clock = item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 220)
        let saved = [app, visible, cc, clock].map(\.uniqueIdentifier)

        let plan = ControlOrderRules.structuralVisibleSegment(
            ordinaryVisibleItems: [app, siri, cc, clock],
            visibleControl: visible,
            savedOrder: saved
        )

        #expect(plan.map(\.uniqueIdentifier) == [app, siri, visible, cc, clock].map(\.uniqueIdentifier))
    }

    @Test
    func structuralPlanKeepsSiriWhereItSitsWithoutASavedOrder() {
        let app = item(MenuBarItemTag(namespace: .string("com.example.app"), title: "Item"), x: 100)
        let siri = item(.siri, x: 130)
        let visible = item(.visibleControlItem, x: 160)
        let cc = item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 190)
        let clock = item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 220)

        let plan = ControlOrderRules.structuralVisibleSegment(
            ordinaryVisibleItems: [app, siri, cc, clock],
            visibleControl: visible,
            savedOrder: []
        )

        #expect(plan.map(\.uniqueIdentifier) == [app, siri, visible, cc, clock].map(\.uniqueIdentifier))
    }

    @Test
    func validationAcceptsSiriAnywhereLeftOfTheAnchors() {
        let siri = item(.siri, x: 100)
        let app = item(MenuBarItemTag(namespace: .string("com.example.app"), title: "Item"), x: 130)
        let cc = item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 160)
        let clock = item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 190)
        #expect(ControlOrderRules.anchoredTrailingViolation(in: [siri, app, cc, clock]) == nil)
        #expect(ControlOrderRules.anchoredTrailingViolation(in: [app, siri, cc, clock]) == nil)
    }

    @Test
    func validationRejectsSiriRightOfTheAnchoredGroup() {
        let cc = item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 160)
        let clock = item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 190)
        let siri = item(.siri, x: 220)
        #expect(ControlOrderRules.anchoredTrailingViolation(in: [cc, clock, siri]) != nil)
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
        #expect(ControlOrderRules.anchoredTrailingViolation(in: [cc, clock, parked]) == nil)
        #expect(ControlOrderRules.anchoredTrailingViolation(in: [cc, clock, onBar]) != nil)
    }
}
