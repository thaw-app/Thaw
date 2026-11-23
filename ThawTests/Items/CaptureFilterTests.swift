//
//  CaptureFilterTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Capture skips items that draw nothing")
struct CaptureFilterTests {
    private func item(_ tag: MenuBarItemTag, width: CGFloat = 20) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: 1,
            ownerPID: 1,
            sourcePID: 1,
            bounds: CGRect(x: 100, y: 3, width: width, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }

    @Test("A hidden Thaw icon collapsed to a sliver is not captured", arguments: [0, 2] as [CGFloat])
    func collapsedVisibleControlIsSkipped(width: CGFloat) {
        #expect(!MenuBarItemImageCache.isCapturable(item(.visibleControlItem, width: width)))
    }

    @Test("A shown Thaw icon is still captured")
    func shownVisibleControlIsCaptured() {
        #expect(MenuBarItemImageCache.isCapturable(item(.visibleControlItem, width: 22)))
    }

    @Test("Dividers stay excluded and app items stay included")
    func otherItemsKeepTheirRule() {
        #expect(!MenuBarItemImageCache.isCapturable(item(.hiddenControlItem)))
        #expect(MenuBarItemImageCache.isCapturable(item(MenuBarItemTag(namespace: .string("com.example.app"), title: "Item"))))
    }

    /// A status item with its icon turned off is a sliver. Revealing it for a
    /// picture covers the bar for nothing, so the prewarm leaves it out.
    @Test(
        "A sliver is blank on the bar or parked off it, a glyph-wide or zero-width frame is not",
        arguments: [
            (CGRect(x: 1598, y: 0, width: 4, height: 33), true),
            (CGRect(x: -1, y: 1105, width: 4, height: 24), true),
            (CGRect(x: 1232, y: 0, width: 20, height: 33), false),
            (CGRect(x: -737, y: 0, width: 20, height: 33), false),
            (CGRect(x: 1598, y: 0, width: 0, height: 33), false),
        ]
    )
    func blankItem(frame: CGRect, isBlank: Bool) {
        #expect(MenuBarItemImageCache.isBlankItem(frame) == isBlank)
    }

    /// One at a time on a notched display, so overflow chevrons do not contaminate thumbnails.
    @Test("A notched display reveals one item at a time, a notchless one batches")
    func revealBatchSize() {
        #expect(MenuBarItemImageCache.revealBatchSize(hasNotch: true) == 1)
        #expect(MenuBarItemImageCache.revealBatchSize(hasNotch: false) > 1)
    }
}
