//
//  ControlOrderRulesDisplaysTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// The order rules judge parked frames against the displays the caller listed once for the pass.
@MainActor
struct ControlOrderRulesDisplaysTests {
    private static let display = CGRect(x: 40000, y: 0, width: 1920, height: 1080)

    private func item(_ tag: MenuBarItemTag, x: CGFloat) -> MenuBarItem {
        MenuBarItem(tag: tag, windowID: 1, ownerPID: 1, sourcePID: 1,
                    bounds: CGRect(x: Self.display.minX + x, y: 3, width: 20, height: 24),
                    title: tag.title, isOnScreen: true)
    }

    @Test("an app right of the anchored group is found on a listed display")
    func anchoredViolationOnListedDisplay() {
        let items = [
            item(MenuBarItemTag(namespace: .menuBarAgent, title: "ControlCenter"), x: 160),
            item(MenuBarItemTag(namespace: .menuBarAgent, title: "Clock"), x: 190),
            item(MenuBarItemTag(namespace: .string("com.example.app"), title: "Item"), x: 300),
        ]
        #expect(ControlOrderRules.anchoredTrailingViolation(in: items, displays: [Self.display]) != nil)
    }
}
