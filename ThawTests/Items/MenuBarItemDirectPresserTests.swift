//
//  MenuBarItemDirectPresserTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins which element the direct press may press for an item.
@Suite("Menu bar item direct presser")
struct MenuBarItemDirectPresserTests {
    @Test("The item's own element is pressed, whether its owner's or its source's")
    func ownElementIsPressable() {
        #expect(MenuBarItemDirectPresser.isPressable(elementPID: 990, for: [990]))
        #expect(MenuBarItemDirectPresser.isPressable(elementPID: 786, for: [786, 990]), "a hosted item's element is MenuBarAgent's")
    }

    @Test("A neighbour's element at the item's reported spot is not pressed")
    func neighbourIsNotPressable() {
        // One Switch reported where Window Manager was drawn.
        #expect(!MenuBarItemDirectPresser.isPressable(elementPID: 964, for: [990]))
    }

    @Test("An item with no known process presses nothing, since the element can't be checked")
    func unknownOwnerIsNotPressable() {
        #expect(!MenuBarItemDirectPresser.isPressable(elementPID: 964, for: [0]))
        #expect(!MenuBarItemDirectPresser.isPressable(elementPID: 964, for: []))
        #expect(!MenuBarItemDirectPresser.isPressable(elementPID: 0, for: [0]))
    }
}
