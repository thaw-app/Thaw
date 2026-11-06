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

@Suite("Appearance overlay Space lookup")
struct OverlaySpaceLookupTests {
    @Test("The display's own Space wins when the query answers")
    func displaySpaceWins() {
        #expect(OverlaySpaceLookup.resolvedSpaceID(displaySpace: 7, activeSpace: 3, ownsActiveMenuBar: true) == 7)
        #expect(OverlaySpaceLookup.resolvedSpaceID(displaySpace: 7, activeSpace: 3, ownsActiveMenuBar: false) == 7)
    }

    @Test("A silent query on the active menu bar's screen falls back to the active Space")
    func silentQueryFallsBack() {
        #expect(OverlaySpaceLookup.resolvedSpaceID(displaySpace: nil, activeSpace: 3, ownsActiveMenuBar: true) == 3)
        #expect(OverlaySpaceLookup.resolvedSpaceID(displaySpace: 0, activeSpace: 3, ownsActiveMenuBar: true) == 3)
    }

    @Test("Another screen has no fallback, since the active Space may not be its own")
    func otherScreenHasNoFallback() {
        #expect(OverlaySpaceLookup.resolvedSpaceID(displaySpace: nil, activeSpace: 3, ownsActiveMenuBar: false) == nil)
        #expect(OverlaySpaceLookup.resolvedSpaceID(displaySpace: 0, activeSpace: 3, ownsActiveMenuBar: false) == nil)
    }

    @Test("No Space known at all reads as none")
    func nothingKnown() {
        #expect(OverlaySpaceLookup.resolvedSpaceID(displaySpace: nil, activeSpace: 0, ownsActiveMenuBar: true) == nil)
    }
}
