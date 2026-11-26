//
//  ControlOrderRulesTests.swift
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

    @Test("Manual re-lays the controls when Thaw's icon is drawn left of the Hidden divider, and only then")
    func manualRelaysInvertedControls() {
        // Positions follow the main display, so the test does not depend on how wide the machine's screen is.
        let dividerX = CGDisplayBounds(CGMainDisplayID()).midX
        let icon = Self.item(.visibleControlItem, x: dividerX - 307, width: 35, windowID: 1)
        let divider = Self.item(.hiddenControlItem, x: dividerX, width: 3, windowID: 2)
        let pair = ControlItemPair(hidden: divider, alwaysHidden: nil)
        #expect(ControlOrderRules.manualRelaysControls(pair, among: [icon, divider]))

        let inOrder = Self.item(.visibleControlItem, x: dividerX + 52, width: 35, windowID: 1)
        #expect(!ControlOrderRules.manualRelaysControls(pair, among: [inOrder, divider]))
        #expect(!ControlOrderRules.manualRelaysControls(nil, among: [icon]), "without a known divider there is no order to judge")
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

    /// The rules judge parked frames against the displays the caller listed once for the pass.
    @Test("An app right of the anchored group is found on a listed display away from the origin")
    func anchoredViolationOnListedDisplay() {
        let display = CGRect(x: 40000, y: 0, width: 1920, height: 1080)
        let items = [
            Self.item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 40160, windowID: 1),
            Self.item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 40190, windowID: 2),
            Self.app("App", x: 40300, windowID: 3),
        ]
        #expect(ControlOrderRules.anchoredTrailingViolation(in: items, displays: [display]) != nil)
    }
}

@MainActor
@Suite("The freshest recorded visible order")
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
