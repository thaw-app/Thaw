//
//  OverlayBarHeightTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

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
