//
//  BlankItemCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
import Testing
@testable import Thaw

/// A status item with its icon turned off is a sliver. Revealing it for a
/// picture covers the bar for nothing, so the prewarm leaves it out.
struct BlankItemCaptureTests {
    @Test("A sliver on the bar is blank")
    func sliverOnTheBar() {
        #expect(MenuBarItemImageCache.isBlankItem(CGRect(x: 1598, y: 0, width: 4, height: 33)))
    }

    @Test("A concealed sliver parked off the bar is blank too")
    func parkedSliver() {
        #expect(MenuBarItemImageCache.isBlankItem(CGRect(x: -1, y: 1105, width: 4, height: 24)))
    }

    @Test("A glyph-wide item is not, on the bar or parked")
    func glyphWide() {
        #expect(!MenuBarItemImageCache.isBlankItem(CGRect(x: 1232, y: 0, width: 20, height: 33)))
        #expect(!MenuBarItemImageCache.isBlankItem(CGRect(x: -737, y: 0, width: 20, height: 33)))
    }

    @Test("A zero-width frame says nothing")
    func zeroWidth() {
        #expect(!MenuBarItemImageCache.isBlankItem(CGRect(x: 1598, y: 0, width: 0, height: 33)))
    }
}
