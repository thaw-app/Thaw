//
//  OverlayLevelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@Suite("Appearance overlay window level")
struct OverlayLevelTests {
    private let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    private let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))

    @Test("On the desktop an appearance sits just under the status items")
    func desktopLevel() {
        let level = MenuBarOverlayPanel.overlayLevel(hasAppearance: true, isFullscreenSpace: false)
        #expect(level.rawValue == statusLevel - 1)
    }

    @Test("In a fullscreen Space an appearance sits under the menu bar itself")
    func fullscreenLevel() {
        let level = MenuBarOverlayPanel.overlayLevel(hasAppearance: true, isFullscreenSpace: true)
        #expect(level.rawValue == mainMenuLevel - 1)
        #expect(level.rawValue < mainMenuLevel)
    }

    @Test("Without an appearance the level does not depend on the Space")
    func noAppearanceLevel() {
        #expect(MenuBarOverlayPanel.overlayLevel(hasAppearance: false, isFullscreenSpace: false) == .statusBar)
        #expect(MenuBarOverlayPanel.overlayLevel(hasAppearance: false, isFullscreenSpace: true) == .statusBar)
    }
}
