//
//  GameModeItemPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import MenuBarModel

@Suite("The Game Mode indicator can be arranged like any other item")
struct GameModeItemPolicyTests {
    @Test func canBeHidden() {
        #expect(MenuBarItemTag.gameMode.sectionManagementPolicy == .hideable)
        #expect(MenuBarItemTag.gameMode.canBeHidden)
    }

    @Test func canBeMoved() {
        #expect(MenuBarItemTag.gameMode.isMovable)
        #expect(!MenuBarItemTag.gameMode.isLayoutAnchoredSystemItem)
    }

    @Test func otherSystemAgentsStayFixed() {
        #expect(!MenuBarItemTag.screenCaptureUI.isMovable)
        #expect(!MenuBarItemTag.screenCaptureUI.canBeHidden)
    }
}
