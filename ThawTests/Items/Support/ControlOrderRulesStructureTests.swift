//
//  ControlOrderRulesStructureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Control order rules write the dividers between their sections")
struct ControlOrderRulesStructureTests {
    private static func item(_ tag: MenuBarItemTag, x: CGFloat, width: CGFloat = 22, windowID: CGWindowID) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: windowID,
            ownerPID: 999_973,
            sourcePID: 999_973,
            bounds: CGRect(x: x, y: 0, width: width, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }

    private static func app(_ title: String, x: CGFloat, windowID: CGWindowID) -> MenuBarItem {
        item(MenuBarItemTag(namespace: .string("com.example.order"), title: title, instanceIndex: 0), x: x, windowID: windowID)
    }

    @Test("The structural order runs Always Hidden, its divider, Hidden, its divider, then Visible")
    func structuralOrderWithBothDividers() {
        let always = Self.app("Always", x: 0, windowID: 1)
        let alwaysDivider = Self.item(.alwaysHiddenControlItem, x: 30, width: 1, windowID: 2)
        let hidden = Self.app("Hidden", x: 40, windowID: 3)
        let hiddenDivider = Self.item(.hiddenControlItem, x: 70, width: 1, windowID: 4)
        let visible = Self.app("Visible", x: 80, windowID: 5)

        let order = ControlOrderRules.structuralOrder(
            alwaysHiddenItems: [always],
            alwaysHiddenControlItem: alwaysDivider,
            hiddenItems: [hidden],
            hiddenControlItem: hiddenDivider,
            visibleSegment: [visible]
        )

        #expect(order.map(\.windowID) == [1, 2, 3, 4, 5])
    }

    @Test("The Always Hidden divider is optional in the structural order")
    func structuralOrderWithoutAlwaysHiddenDivider() {
        let hiddenDivider = Self.item(.hiddenControlItem, x: 70, width: 1, windowID: 4)
        let order = ControlOrderRules.structuralOrder(
            alwaysHiddenItems: [],
            alwaysHiddenControlItem: nil,
            hiddenItems: [],
            hiddenControlItem: hiddenDivider,
            visibleSegment: []
        )
        #expect(order.map(\.windowID) == [4])
    }

    @Test("Without a visible control nothing is stranded")
    func noVisibleControlIsNotStranded() {
        #expect(!ControlOrderRules.visibleControlIsStranded(among: [Self.app("A", x: 100, windowID: 1)]))
    }

    @Test("A visible control parked at the sentinel x is stranded")
    func sentinelVisibleControlIsStranded() {
        let display = CGDisplayBounds(CGMainDisplayID())
        let parked = MenuBarItem(
            tag: .visibleControlItem,
            windowID: 9,
            ownerPID: 999_973,
            sourcePID: 999_973,
            bounds: CGRect(x: -1, y: display.maxY + 500, width: 22, height: 24),
            title: nil,
            isOnScreen: true
        )
        #expect(ControlOrderRules.visibleControlIsStranded(among: [parked]))
    }

    @Test("A non-anchored item right of an anchored system item is a violation")
    func nonAnchoredAfterAnchored() {
        let clock = Self.item(.clock, x: 100, windowID: 1)
        let app = Self.app("App", x: 200, windowID: 2)
        let display = CGRect(x: 0, y: 0, width: 2000, height: 1000)

        let violation = ControlOrderRules.anchoredTrailingViolation(in: [clock, app], displays: [display])

        #expect(violation?.contains("sits right of the anchored trailing group") == true)
        #expect(ControlOrderRules.anchoredTrailingViolation(in: [app, clock], displays: [display]) == nil)
    }
}
