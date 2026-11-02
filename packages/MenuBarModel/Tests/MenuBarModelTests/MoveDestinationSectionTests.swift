//
//  MoveDestinationSectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import MenuBarModel
import Testing

struct MoveDestinationSectionTests {
    @Test("Boundary crossings use the requested side, not the mover's identity", arguments: [
        (MenuBarItemTag.hiddenControlItem, MenuBarSectionName.hidden, Optional(MenuBarSectionName.visible)),
        (.alwaysHiddenControlItem, .alwaysHidden, .hidden),
        (.visibleControlItem, .visible, nil),
    ])
    func crossingSides(tag: MenuBarItemTag, left: MenuBarSectionName, right: MenuBarSectionName?) {
        let mover = item(tag: MenuBarItemTag(namespace: .string("test.app"), title: "Item"))
        let anchor = item(tag: tag)
        #expect(MoveDestination.leftOfItem(anchor).sectionAcrossBoundary(from: mover) == left)
        #expect(MoveDestination.rightOfItem(anchor).sectionAcrossBoundary(from: mover) == right)
    }

    @Test("An ordinary neighbour is not a section crossing")
    func ordinaryTarget() {
        let mover = item(tag: MenuBarItemTag(namespace: .string("test.app"), title: "Item"))
        let anchor = item(tag: MenuBarItemTag(namespace: .string("test.other"), title: "Other"))
        #expect(MoveDestination.leftOfItem(anchor).sectionAcrossBoundary(from: mover) == nil)
        #expect(MoveDestination.rightOfItem(anchor).sectionAcrossBoundary(from: mover) == nil)
    }

    @Test("A rediscovered control cannot be moved across itself")
    func selfTarget() {
        let mover = item(tag: .hiddenControlItem)
        let anchor = item(tag: .hiddenControlItem, windowID: 2)
        #expect(MoveDestination.leftOfItem(anchor).sectionAcrossBoundary(from: mover) == nil)
        #expect(MoveDestination.rightOfItem(anchor).sectionAcrossBoundary(from: mover) == nil)
    }

    private func item(tag: MenuBarItemTag, windowID: CGWindowID = 1) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: windowID,
            ownerPID: 42,
            sourcePID: nil,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }
}
