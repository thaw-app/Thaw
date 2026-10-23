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

/// A status item with its icon turned off is a sliver on the bar. Revealing it
/// for a picture covers the bar for nothing, so the prewarm leaves it out.
struct BlankItemCaptureTests {
    private let displays = [CGRect(x: 0, y: 0, width: 1728, height: 1117)]

    @Test("A sliver on the bar is blank")
    func sliverOnTheBar() {
        #expect(MenuBarItemImageCache.isBlankOnTheBar(CGRect(x: 1598, y: 0, width: 4, height: 33), displays: displays))
    }

    @Test("A glyph-wide item on the bar is not")
    func glyphOnTheBar() {
        #expect(!MenuBarItemImageCache.isBlankOnTheBar(CGRect(x: 1232, y: 0, width: 20, height: 33), displays: displays))
    }

    @Test("A sliver parked off every display is a concealed item, not a blank one")
    func parkedSliver() {
        #expect(!MenuBarItemImageCache.isBlankOnTheBar(CGRect(x: -737, y: 0, width: 4, height: 33), displays: displays))
    }

    @Test("A zero-width frame says nothing")
    func zeroWidth() {
        #expect(!MenuBarItemImageCache.isBlankOnTheBar(CGRect(x: 1598, y: 0, width: 0, height: 33), displays: displays))
    }
}
