//
//  NewItemRouteTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A new item reaches the section the New Items setting names")
struct NewItemRouteTests {
    @Test("A newcomer bound for a concealed section's divider is assigned the section", arguments: [
        MenuBarSectionName.hidden, .alwaysHidden,
    ])
    func concealedSectionIsAssigned(section: MenuBarSectionName) {
        #expect(NewItemRoute(section: section, destinationIsDivider: true) == .assign)
    }

    @Test("A newcomer with an anchor item to sit beside is moved there")
    func anchoredNewcomerIsMoved() {
        #expect(NewItemRoute(section: .hidden, destinationIsDivider: false) == .move)
        #expect(NewItemRoute(section: .visible, destinationIsDivider: false) == .move)
    }

    @Test("A newcomer bound for Visible keeps the move, since it is Visible already")
    func visibleKeepsTheMove() {
        #expect(NewItemRoute(section: .visible, destinationIsDivider: true) == .move)
    }
}
