//
//  GhostControlItemWindowTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

@MainActor
@Suite("GhostControlItemWindow")
struct GhostControlItemWindowTests {
    private let hiddenTitle = "Thaw.ControlItem.Hidden"
    private let alwaysHiddenTitle = "Thaw.ControlItem.AlwaysHidden"

    private func item(tag: MenuBarItemTag, windowID: CGWindowID, title: String) -> MenuBarItem {
        MenuBarItem.fixture(tag: tag, windowID: windowID, title: title)
    }

    @Test("ControlItemPair prefers authoritative window IDs")
    func controlItemPairPrefersAuthoritativeWindowIDs() {
        var items = [
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
            item(tag: .alwaysHiddenControlItem, windowID: 366, title: alwaysHiddenTitle),
            item(
                tag: .appItem(bundleID: "com.stonerl.Thaw", title: hiddenTitle, instanceIndex: 1),
                windowID: 21542,
                title: hiddenTitle
            ),
            item(
                tag: .appItem(bundleID: "com.stonerl.Thaw", title: alwaysHiddenTitle, instanceIndex: 1),
                windowID: 21543,
                title: alwaysHiddenTitle
            ),
        ]

        let pair = MenuBarItemManager.ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: 21542,
            alwaysHiddenControlItemWindowID: 21543
        )

        #expect(pair?.hidden.windowID == 21542)
        #expect(pair?.alwaysHidden?.windowID == 21543)
        #expect(items.map(\.windowID) == [364, 366])
    }

    @Test("ControlItemPair falls back to tag lookup without window IDs")
    func controlItemPairFallsBackToTagLookupWithoutWindowIDs() {
        var items = [
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
            item(tag: .alwaysHiddenControlItem, windowID: 366, title: alwaysHiddenTitle),
        ]

        let pair = MenuBarItemManager.ControlItemPair(items: &items)

        #expect(pair?.hidden.windowID == 364)
        #expect(pair?.alwaysHidden?.windowID == 366)
        #expect(items.isEmpty)
    }

    @Test("ControlItemPair does not adopt a foreign always-hidden window")
    func controlItemPairDoesNotAdoptForeignAlwaysHiddenWindow() {
        var items = [
            item(tag: .alwaysHiddenControlItem, windowID: 366, title: alwaysHiddenTitle),
            item(
                tag: .appItem(bundleID: "com.stonerl.Thaw", title: hiddenTitle, instanceIndex: 1),
                windowID: 21542,
                title: hiddenTitle
            ),
        ]

        let pair = MenuBarItemManager.ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: 21542,
            alwaysHiddenControlItemWindowID: 21543
        )

        #expect(pair?.hidden.windowID == 21542)
        #expect(pair?.alwaysHidden == nil)
    }

    @Test("Ghost detection drops only the foreign control window")
    func ghostDetectionDropsOnlyForeignControlWindow() {
        let items = [
            item(
                tag: .appItem(bundleID: "com.stonerl.Thaw", title: hiddenTitle, instanceIndex: 1),
                windowID: 21542,
                title: hiddenTitle
            ),
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
            item(tag: .appItem(bundleID: "com.apple.controlcenter", title: "Battery"), windowID: 850, title: "Battery"),
        ]

        let ghosts = MenuBarItemManager.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: [hiddenTitle: 21542]
        )

        #expect(ghosts == [364])
    }

    @Test("Ghost detection requires the authoritative window")
    func ghostDetectionRequiresTheAuthoritativeWindow() {
        let items = [item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle)]

        let ghosts = MenuBarItemManager.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: [hiddenTitle: 21542]
        )

        #expect(ghosts.isEmpty)
    }
}
