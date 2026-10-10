//
//  MenuBarItemImageCacheIdleTrimTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins MenuBarItemImageCache.idleTrimSurvivors(cachedTags:concealedTags:),
/// the selection the idle trim uses to keep glyphs that only a reveal on the
/// live menu bar can refill. Visible-section images may go; images for items
/// in a concealed section stay, matched without regard to the window ID
/// because disk-loaded captures carry none.
@Suite("Idle trim survivors")
struct MenuBarItemImageCacheIdleTrimTests {
    private static func tag(_ bundleID: String, _ title: String, windowID: CGWindowID? = nil) -> MenuBarItemTag {
        MenuBarItemTag(namespace: .string(bundleID), title: title, windowID: windowID)
    }

    @Test("nothing survives when no section is concealed")
    func nothingConcealedDropsEverything() {
        let cached = [Self.tag("com.a", "A", windowID: 1), Self.tag("com.b", "B", windowID: 2)]
        #expect(MenuBarItemImageCache.idleTrimSurvivors(cachedTags: cached, concealedTags: []).isEmpty)
    }

    @Test("only concealed items' images are kept")
    func keepsConcealedDropsVisible() {
        let visible = Self.tag("com.visible", "V", windowID: 1)
        let hidden = Self.tag("com.hidden", "H", windowID: 2)
        let alwaysHidden = Self.tag("com.always", "AH", windowID: 3)
        let survivors = MenuBarItemImageCache.idleTrimSurvivors(
            cachedTags: [visible, hidden, alwaysHidden],
            concealedTags: [hidden, alwaysHidden]
        )
        #expect(survivors == [hidden, alwaysHidden])
    }

    @Test("a disk-loaded key without a window ID matches its live concealed item")
    func matchesIgnoringWindowID() {
        let diskKey = Self.tag("com.hidden", "H")
        let liveItem = Self.tag("com.hidden", "H", windowID: 42)
        let survivors = MenuBarItemImageCache.idleTrimSurvivors(
            cachedTags: [diskKey],
            concealedTags: [liveItem]
        )
        #expect(survivors == [diskKey])
    }

    @Test("a concealed item with no cached image contributes nothing")
    func concealedWithoutImageIsIgnored() {
        let cachedVisible = Self.tag("com.visible", "V", windowID: 1)
        let concealedUncached = Self.tag("com.hidden", "H", windowID: 2)
        let survivors = MenuBarItemImageCache.idleTrimSurvivors(
            cachedTags: [cachedVisible],
            concealedTags: [concealedUncached]
        )
        #expect(survivors.isEmpty)
    }
}
