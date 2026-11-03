//
//  AbsentAppSiblingsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Native hiding keeps an app on the bar while any of its items is placed in Visible, drawn or not,
/// so a drop takes along the app's items Layout can't show.
@Suite("Absent app siblings")
struct AbsentAppSiblingsTests {
    private func item(_ bundle: String, _ title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: title, windowID: 1, instanceIndex: 0),
            windowID: 1,
            ownerPID: 42,
            sourcePID: 42,
            bounds: CGRect(x: 900, y: 0, width: 24, height: 24),
            title: nil,
            isOnScreen: true
        )
    }

    private let droppy = "iordv.Droppy"

    @Test("An app's items placed elsewhere and not on the bar follow the dropped one")
    func undrawnSiblingsFollow() {
        let dropped = item(droppy, "DroppyMenuBar")
        let moved = AbsentAppSiblings.identifiers(
            following: [dropped],
            to: .hidden,
            assignment: [
                "iordv.Droppy:DroppyMenuBar": .hidden,
                "iordv.Droppy:Item-0": .visible,
                "iordv.Droppy:LiquidPlayerMenuBar": .visible,
                "com.example.Other:Item-0": .visible,
            ],
            liveIdentifiers: ["iordv.Droppy:DroppyMenuBar", "com.example.Other:Item-0"]
        )
        #expect(moved == ["iordv.Droppy:Item-0", "iordv.Droppy:LiquidPlayerMenuBar"])
    }

    @Test("A sibling on the bar, one already in the target, and another app's lookalike prefix stay put")
    func onlyAbsentSiblingsOfTheSameAppMove() {
        let moved = AbsentAppSiblings.identifiers(
            following: [item(droppy, "DroppyMenuBar")],
            to: .hidden,
            assignment: [
                "iordv.Droppy:Live": .visible,
                "iordv.Droppy:AlreadyThere": .hidden,
                "iordv.DroppyHelper:Item-0": .visible,
            ],
            liveIdentifiers: ["iordv.Droppy:Live"]
        )
        #expect(moved.isEmpty)
    }

    @Test("Items that aren't grouped by app, such as Apple's, bring nothing along")
    func systemItemsBringNothing() {
        let moved = AbsentAppSiblings.identifiers(
            following: [item("com.apple.MenuBarAgent", "com.apple.menuextra.wifi")],
            to: .hidden,
            assignment: ["com.apple.MenuBarAgent:com.apple.menuextra.bluetooth": .visible],
            liveIdentifiers: []
        )
        #expect(moved.isEmpty)
    }
}
