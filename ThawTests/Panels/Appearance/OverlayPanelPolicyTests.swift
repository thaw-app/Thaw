//
//  OverlayPanelPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import QuartzCore
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

@Suite("Appearance overlay height", .bug("https://github.com/thaw-app/Thaw/issues/1229"))
struct OverlayBarHeightTests {
    private func height(
        window: CGFloat, menu: CGFloat?, fullscreen: Bool, ownMenuFrame: Bool = true
    ) -> CGFloat {
        MenuBarOverlayPanel.overlayBarHeight(
            windowHeight: window,
            applicationMenuHeight: menu,
            isFullscreenSpace: fullscreen,
            readsOwnMenuFrame: ownMenuFrame
        )
    }

    @Test("In a fullscreen Space a window taller than the drawn bar is capped to the bar")
    func fullscreenCapsToTheDrawnBar() {
        #expect(height(window: 55, menu: 33, fullscreen: true) == 33)
    }

    @Test("On the desktop the window's height stands")
    func desktopKeepsTheWindowHeight() {
        #expect(height(window: 55, menu: 33, fullscreen: false) == 55)
    }

    @Test("The cap never makes the bar taller, and needs a usable menu height")
    func capOnlyShrinks() {
        #expect(height(window: 30, menu: 30, fullscreen: true) == 30)
        #expect(height(window: 30, menu: 44, fullscreen: true) == 30)
        #expect(height(window: 55, menu: nil, fullscreen: true) == 55)
        #expect(height(window: 55, menu: 0, fullscreen: true) == 55)
    }

    @Test("A screen that borrows the main screen's menu frame keeps its own window height")
    func borrowedMenuFrameIsNotTrusted() {
        #expect(height(window: 38, menu: 30, fullscreen: true, ownMenuFrame: false) == 38)
    }
}

/// The overlay's fade while a menu bar item is dragged.
@Suite("Overlay drag fade")
struct OverlayDragFadeTests {
    @Test("Fading out is quicker than fading back in")
    func outIsQuicker() {
        #expect(OverlayDragFade.duration(from: 1, to: 0, reduceMotion: false) == 0.15)
        #expect(OverlayDragFade.duration(from: 0, to: 1, reduceMotion: false) == 0.2)
    }

    @Test("A fade reversed partway takes only the share the distance left needs")
    func reversalIsScaled() {
        let duration = OverlayDragFade.duration(from: 0.25, to: 1, reduceMotion: false)
        #expect(abs(duration - 0.15) < 0.0001)
        #expect(OverlayDragFade.duration(from: 1, to: 1, reduceMotion: false) == 0)
    }

    @Test("The curve starts fast and lands soft")
    func curveIsEaseOut() {
        var first = [Float](repeating: 0, count: 2)
        var second = [Float](repeating: 0, count: 2)
        OverlayDragFade.timing.getControlPoint(at: 1, values: &first)
        OverlayDragFade.timing.getControlPoint(at: 2, values: &second)
        #expect(first == [0.23, 1])
        #expect(second == [0.32, 1])
    }

    @Test("Reduce Motion keeps a short fade instead of a cut")
    func reduceMotionCaps() {
        #expect(OverlayDragFade.duration(from: 1, to: 0, reduceMotion: true) == 0.1)
        #expect(OverlayDragFade.duration(from: 0, to: 1, reduceMotion: true) == 0.1)
    }
}
