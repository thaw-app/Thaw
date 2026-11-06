//
//  CaptureGeometryRulesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins where a capture reads from: the display it picks, whether a section
/// needs live bounds, and which items have a rectangle worth cropping.
@MainActor
@Suite("Capture geometry rules")
struct CaptureGeometryRulesTests {
    private static func item(
        _ title: String,
        x: CGFloat,
        width: CGFloat = 24,
        windowID: CGWindowID
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 501,
            sourcePID: 501,
            bounds: CGRect(x: x, y: 4, width: width, height: 22),
            title: title,
            isOnScreen: true
        )
    }

    // MARK: captureDisplayID

    @Test("The item cache's display wins over the other two")
    func itemCacheDisplayWins() {
        #expect(MenuBarItemImageCache.captureDisplayID(
            itemCacheDisplayID: 1, activeMenuBarDisplayID: 2, mainDisplayID: 3
        ) == 1)
        #expect(MenuBarItemImageCache.captureDisplayID(
            itemCacheDisplayID: 1, activeMenuBarDisplayID: nil, mainDisplayID: 3
        ) == 1)
    }

    @Test("Without an item cache display, the display owning the menu bar is used")
    func activeMenuBarDisplayIsSecond() {
        #expect(MenuBarItemImageCache.captureDisplayID(
            itemCacheDisplayID: nil, activeMenuBarDisplayID: 2, mainDisplayID: 3
        ) == 2)
    }

    @Test("The main display is the last resort")
    func mainDisplayIsLast() {
        #expect(MenuBarItemImageCache.captureDisplayID(
            itemCacheDisplayID: nil, activeMenuBarDisplayID: nil, mainDisplayID: 3
        ) == 3)
    }

    // MARK: shouldUseFreshBounds

    @Test(
        "The visible section always reads fresh bounds",
        arguments: [nil, MenuBarSection.Name.visible, .hidden, .alwaysHidden]
    )
    func visibleAlwaysUsesFreshBounds(revealed: MenuBarSection.Name?) {
        #expect(MenuBarItemImageCache.shouldUseFreshBounds(for: .visible, revealedSection: revealed))
    }

    @Test(
        "A concealed section reads fresh bounds while a reveal uncovers it",
        arguments: [
            (MenuBarSection.Name.hidden, MenuBarSection.Name.hidden),
            (.hidden, .alwaysHidden),
            (.alwaysHidden, .alwaysHidden),
        ]
    )
    func revealedSectionUsesFreshBounds(section: MenuBarSection.Name, revealed: MenuBarSection.Name) {
        #expect(MenuBarItemImageCache.shouldUseFreshBounds(for: section, revealedSection: revealed))
    }

    @Test(
        "A concealed section keeps its cached bounds while no reveal uncovers it",
        arguments: [
            (MenuBarSection.Name.hidden, MenuBarSection.Name?.none),
            (.hidden, .visible),
            (.alwaysHidden, nil),
            (.alwaysHidden, .visible),
            (.alwaysHidden, .hidden),
        ]
    )
    func concealedSectionKeepsCachedBounds(section: MenuBarSection.Name, revealed: MenuBarSection.Name?) {
        let usesFreshBounds = MenuBarItemImageCache.shouldUseFreshBounds(for: section, revealedSection: revealed)
        #expect(usesFreshBounds == false)
    }

    // MARK: captureBounds

    @Test("Cached bounds are used as they are when fresh bounds are not asked for")
    func cachedBoundsAreUsed() {
        let first = Self.item("First", x: 100, windowID: 1)
        let second = Self.item("Second", x: 200, windowID: 2)

        let result = MenuBarItemImageCache.captureBounds(
            for: [first, second],
            freshBounds: false,
            // Ignored without freshBounds.
            liveBoundsByID: [first.uniqueIdentifier: CGRect(x: 900, y: 4, width: 24, height: 22)],
            screenFrame: nil
        )

        #expect(result.map(\.item.windowID) == [1, 2])
        #expect(result.map(\.bounds) == [first.bounds, second.bounds])
    }

    @Test("Fresh bounds come from the live lookup, and an item missing from it is dropped")
    func freshBoundsComeFromTheLookup() {
        let found = Self.item("Found", x: 100, windowID: 1)
        let missing = Self.item("Missing", x: 200, windowID: 2)
        let live = CGRect(x: 640, y: 4, width: 30, height: 22)

        let result = MenuBarItemImageCache.captureBounds(
            for: [found, missing],
            freshBounds: true,
            liveBoundsByID: [found.uniqueIdentifier: live],
            screenFrame: nil
        )

        #expect(result.map(\.item.windowID) == [1])
        #expect(result.map(\.bounds) == [live])
    }

    @Test("An empty rectangle is dropped, cached or fresh")
    func emptyBoundsAreDropped() {
        let collapsed = Self.item("Collapsed", x: 100, width: 0, windowID: 1)
        let healthy = Self.item("Healthy", x: 200, windowID: 2)

        let cached = MenuBarItemImageCache.captureBounds(
            for: [collapsed, healthy], freshBounds: false, liveBoundsByID: [:], screenFrame: nil
        )
        #expect(cached.map(\.item.windowID) == [2])

        let fresh = MenuBarItemImageCache.captureBounds(
            for: [healthy],
            freshBounds: true,
            liveBoundsByID: [healthy.uniqueIdentifier: .zero],
            screenFrame: nil
        )
        #expect(fresh.isEmpty)
    }

    @Test("Only items overlapping the screen's horizontal span are kept")
    func horizontalOverlapFilters() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let inside = Self.item("Inside", x: 500, windowID: 1)
        let straddlingRight = Self.item("StraddlingRight", x: 990, windowID: 2)
        let straddlingLeft = Self.item("StraddlingLeft", x: -10, windowID: 3)
        // Touching an edge is not overlapping it.
        let touchingRight = Self.item("TouchingRight", x: 1000, windowID: 4)
        let touchingLeft = Self.item("TouchingLeft", x: -24, windowID: 5)
        let nextDisplay = Self.item("NextDisplay", x: 1500, windowID: 6)

        let result = MenuBarItemImageCache.captureBounds(
            for: [inside, straddlingRight, straddlingLeft, touchingRight, touchingLeft, nextDisplay],
            freshBounds: false,
            liveBoundsByID: [:],
            screenFrame: screen
        )

        #expect(result.map(\.item.windowID) == [1, 2, 3])
    }

    @Test("The vertical position never filters, since the two coordinate spaces disagree on it")
    func verticalPositionIsIgnored() {
        let item = Self.item("Item", x: 500, windowID: 1)

        let result = MenuBarItemImageCache.captureBounds(
            for: [item],
            freshBounds: false,
            liveBoundsByID: [:],
            screenFrame: CGRect(x: 0, y: 5000, width: 1000, height: 600)
        )

        #expect(result.map(\.item.windowID) == [1])
    }

    @Test("The overlap filter applies to fresh bounds, not to the cached ones")
    func overlapFilterUsesFreshBounds() {
        let item = Self.item("Item", x: 500, windowID: 1)

        let result = MenuBarItemImageCache.captureBounds(
            for: [item],
            freshBounds: true,
            liveBoundsByID: [item.uniqueIdentifier: CGRect(x: 1500, y: 4, width: 24, height: 22)],
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        #expect(result.isEmpty)
    }
}
