//
//  CaptureDemandRulesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins what asks for a capture: the item cache state that invalidates the
/// last one, the sections a live scope covers, and how one pass folds its
/// sections together.
@MainActor
@Suite("Capture demand rules")
struct CaptureDemandRulesTests {
    private static func item(
        _ title: String,
        bounds: CGRect = CGRect(x: 100, y: 4, width: 24, height: 22),
        windowID: CGWindowID,
        isOnScreen: Bool = true
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 501,
            sourcePID: 501,
            bounds: bounds,
            title: title,
            isOnScreen: isOnScreen
        )
    }

    private static func cache(
        displayID: CGDirectDisplayID? = 7,
        visible: [MenuBarItem] = [],
        hidden: [MenuBarItem] = []
    ) -> MenuBarItemCache {
        var cache = MenuBarItemCache(displayID: displayID)
        cache[.visible] = visible
        cache[.hidden] = hidden
        return cache
    }

    private static func capture(width: Int) throws -> MenuBarItemGlyphCapture {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try MenuBarItemGlyphCapture(cgImage: #require(context.makeImage()), scale: 1)
    }

    // MARK: captureInvalidationKey

    @Test("An item that only moved does not ask for a new capture")
    func positionIsLeftOut() {
        let before = Self.item("A", bounds: CGRect(x: 100, y: 4, width: 24, height: 22), windowID: 1)
        let after = Self.item("A", bounds: CGRect(x: 131, y: 5, width: 24, height: 22), windowID: 1)

        #expect(
            MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [before]))
                == MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [after]))
        )
    }

    @Test("A change of size, window, visibility, section or display asks for one")
    func everythingElseCounts() {
        let item = Self.item("A", windowID: 1)
        let key = MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [item]))

        let resized = Self.item("A", bounds: CGRect(x: 100, y: 4, width: 30, height: 22), windowID: 1)
        let taller = Self.item("A", bounds: CGRect(x: 100, y: 4, width: 24, height: 24), windowID: 1)
        let rehosted = Self.item("A", windowID: 2)
        let offScreen = Self.item("A", windowID: 1, isOnScreen: false)

        for changed in [resized, taller, rehosted, offScreen] {
            #expect(MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [changed])) != key)
        }
        #expect(MenuBarItemImageCache.captureInvalidationKey(Self.cache(hidden: [item])) != key)
        #expect(MenuBarItemImageCache.captureInvalidationKey(Self.cache(displayID: 8, visible: [item])) != key)
        #expect(MenuBarItemImageCache.captureInvalidationKey(Self.cache(displayID: nil, visible: [item])) != key)
        #expect(MenuBarItemImageCache.captureInvalidationKey(Self.cache()) != key)
    }

    @Test("The order items are listed in within a section does not matter")
    func orderWithinASectionIsLeftOut() {
        let first = Self.item("A", windowID: 1)
        let second = Self.item("B", windowID: 2)

        let key = MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [first, second]))

        #expect(key == MenuBarItemImageCache.captureInvalidationKey(Self.cache(visible: [second, first])))
        #expect(key.displayID == 7)
        #expect(key.entries.map(\.windowID) == [1, 2])
    }

    @Test("Entries sort by section, then identifier, then window")
    func entryOrdering() {
        typealias Entry = MenuBarItemImageCache.CaptureInvalidationKey.Entry
        func entry(_ section: String, _ identifier: String, _ windowID: CGWindowID) -> Entry {
            Entry(section: section, identifier: identifier, windowID: windowID, width: 24, height: 22, isOnScreen: true)
        }

        #expect(entry("a", "z", 9) < entry("b", "a", 1))
        #expect(entry("a", "a", 9) < entry("a", "b", 1))
        #expect(entry("a", "a", 1) < entry("a", "a", 2))
        #expect(!(entry("a", "a", 1) < entry("a", "a", 1)))
    }

    // MARK: LiveCaptureScope

    @Test("Each scope names the sections it captures")
    func scopeSections() {
        typealias Scope = MenuBarItemImageCache.LiveCaptureScope

        #expect(Scope.none.sections(thawBarSection: .hidden).isEmpty)
        #expect(Scope.visible.sections(thawBarSection: .hidden) == [.visible])
        #expect(Scope.allSections.sections(thawBarSection: nil) == MenuBarSection.Name.allCases)
        #expect(Scope.thawBar.sections(thawBarSection: .alwaysHidden) == [.alwaysHidden])
    }

    @Test("The Thaw Bar scope captures nothing while the bar shows no section")
    func thawBarWithoutASection() {
        #expect(MenuBarItemImageCache.LiveCaptureScope.thawBar.sections(thawBarSection: nil).isEmpty)
    }

    // MARK: CapturePass

    @Test("Absorbing a section adds everything it learned")
    func absorbAddsEverything() throws {
        let first = Self.item("A", windowID: 1)
        let second = Self.item("B", windowID: 2)
        let third = Self.item("C", windowID: 3)

        var pass = MenuBarItemImageCache.CapturePass()
        pass.captured[first.tag] = try Self.capture(width: 20)
        pass.unreadable = [first]
        pass.invalidatedTags = [first.tag]
        pass.unconditionallyInvalidatedTags = [first.tag]
        pass.failedCaptureItems = [first]
        pass.recoveredItems = [first]
        pass.forgivenTags = [first.tag]

        var section = MenuBarItemImageCache.CapturePass()
        section.captured[second.tag] = try Self.capture(width: 22)
        section.unreadable = [second]
        section.invalidatedTags = [second.tag]
        section.unconditionallyInvalidatedTags = [third.tag]
        section.failedCaptureItems = [second, third]
        section.recoveredItems = [second]
        section.forgivenTags = [third.tag]

        pass.absorb(section)

        #expect(Set(pass.captured.keys) == [first.tag, second.tag])
        #expect(pass.unreadable.map(\.windowID) == [1, 2])
        #expect(pass.invalidatedTags == [first.tag, second.tag])
        #expect(pass.unconditionallyInvalidatedTags == [first.tag, third.tag])
        #expect(pass.failedCaptureItems.map(\.windowID) == [1, 2, 3])
        #expect(pass.recoveredItems.map(\.windowID) == [1, 2])
        #expect(pass.forgivenTags == [first.tag, third.tag])
    }

    @Test("A later section's crop replaces an earlier one for the same item")
    func absorbPrefersTheLaterCrop() throws {
        let item = Self.item("A", windowID: 1)
        let earlier = try Self.capture(width: 20)
        let later = try Self.capture(width: 22)

        var pass = MenuBarItemImageCache.CapturePass()
        pass.captured[item.tag] = earlier
        var section = MenuBarItemImageCache.CapturePass()
        section.captured[item.tag] = later

        pass.absorb(section)

        #expect(pass.captured[item.tag] == later)
    }
}
