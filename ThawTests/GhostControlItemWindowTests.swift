//
//  GhostControlItemWindowTests.swift
//  Project: Thaw
//

import CoreGraphics
@testable import Thaw
import XCTest

final class GhostControlItemWindowTests: XCTestCase {
    private let hiddenTitle = "Thaw.ControlItem.Hidden"
    private let alwaysHiddenTitle = "Thaw.ControlItem.AlwaysHidden"

    private func item(tag: MenuBarItemTag, windowID: CGWindowID, title: String) -> MenuBarItem {
        MenuBarItem.fixture(tag: tag, windowID: windowID, title: title)
    }

    func testControlItemPairPrefersAuthoritativeWindowIDs() {
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

        XCTAssertEqual(pair?.hidden.windowID, 21542)
        XCTAssertEqual(pair?.alwaysHidden?.windowID, 21543)
        XCTAssertEqual(items.map(\.windowID), [364, 366])
    }

    func testControlItemPairFallsBackToTagLookupWithoutWindowIDs() {
        var items = [
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
            item(tag: .alwaysHiddenControlItem, windowID: 366, title: alwaysHiddenTitle),
        ]

        let pair = MenuBarItemManager.ControlItemPair(items: &items)

        XCTAssertEqual(pair?.hidden.windowID, 364)
        XCTAssertEqual(pair?.alwaysHidden?.windowID, 366)
        XCTAssertTrue(items.isEmpty)
    }

    func testControlItemPairDoesNotAdoptForeignAlwaysHiddenWindow() {
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

        XCTAssertEqual(pair?.hidden.windowID, 21542)
        XCTAssertNil(pair?.alwaysHidden)
    }

    func testGhostDetectionDropsOnlyForeignControlWindow() {
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

        XCTAssertEqual(ghosts, [364])
    }

    func testGhostDetectionRequiresTheAuthoritativeWindow() {
        let items = [item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle)]

        let ghosts = MenuBarItemManager.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: [hiddenTitle: 21542]
        )

        XCTAssertTrue(ghosts.isEmpty)
    }
}
