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
}
