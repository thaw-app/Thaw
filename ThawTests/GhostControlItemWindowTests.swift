//
//  GhostControlItemWindowTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Characterizes how a Thaw instance protects itself from control item
/// windows it does not own.
///
/// On macOS 26 every status item window is hosted by Control Center, so a
/// second Thaw instance (or a crashed one) leaves windows in the bar that
/// carry our control item titles. Field failure: the foreign windows held
/// lower windowIDs, won the un-suffixed tag in `assignStableInstanceIndices`,
/// and the newer instance anchored its entire layout to the other instance's
/// dividers while parking its own chevron offscreen as an "unmanaged item".
final class GhostControlItemWindowTests: XCTestCase {
    private let hiddenTitle = "Thaw.ControlItem.Hidden"
    private let alwaysHiddenTitle = "Thaw.ControlItem.AlwaysHidden"

    private func item(
        tag: MenuBarItemTag,
        windowID: CGWindowID,
        title: String
    ) -> MenuBarItem {
        MenuBarItem.fixture(tag: tag, windowID: windowID, title: title)
    }

    // MARK: ControlItemPair authoritative windowID lookup

    /// The foreign dividers hold the un-suffixed tags (lower windowIDs), but
    /// the pair must select the windows whose IDs match this instance's own
    /// NSStatusItem windows.
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
        // Only the selected pair is removed; the foreign windows are handled
        // by the ghost filter, not by pair discovery.
        XCTAssertEqual(items.map(\.windowID), [364, 366])
    }

    /// Without authoritative windowIDs the tag lookup remains the fallback.
    func testControlItemPairFallsBackToTagLookup() {
        var items = [
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
            item(tag: .alwaysHiddenControlItem, windowID: 366, title: alwaysHiddenTitle),
        ]

        let pair = MenuBarItemManager.ControlItemPair(items: &items)

        XCTAssertEqual(pair?.hidden.windowID, 364)
        XCTAssertEqual(pair?.alwaysHidden?.windowID, 366)
        XCTAssertTrue(items.isEmpty)
    }

    /// An authoritative hidden windowID that is missing from the list (stale
    /// window number, filtered fetch) must not disable discovery entirely —
    /// the tag lookup still runs.
    func testControlItemPairMissingAuthoritativeIDFallsBackToTagLookup() {
        var items = [
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
        ]

        let pair = MenuBarItemManager.ControlItemPair(
            items: &items,
            hiddenControlItemWindowID: 99999
        )

        XCTAssertEqual(pair?.hidden.windowID, 364)
        XCTAssertNil(pair?.alwaysHidden)
    }

    /// When the hidden window matched by ID but the known always-hidden ID is
    /// absent from the list, the pair must not adopt a foreign always-hidden
    /// window via the tag lookup.
    func testControlItemPairDoesNotAdoptForeignAlwaysHiddenWhenIDKnown() {
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
            alwaysHiddenControlItemWindowID: 21543 // not in the list
        )

        XCTAssertEqual(pair?.hidden.windowID, 21542)
        XCTAssertNil(pair?.alwaysHidden)
    }

    // MARK: Ghost window detection

    /// A window that claims a control item title while this instance's own
    /// window for that title is present under a different ID is a ghost.
    func testGhostDetectionDropsForeignDuplicates() {
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

    /// Self-check: when this instance's own window is absent from the list,
    /// the window numbers can't be trusted against it, so nothing is dropped.
    func testGhostDetectionRequiresOwnWindowPresent() {
        let items = [
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
        ]

        let ghosts = MenuBarItemManager.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: [hiddenTitle: 21542]
        )

        XCTAssertTrue(ghosts.isEmpty)
    }

    /// No authoritative windows known (startup, permissions): no drops.
    func testGhostDetectionWithEmptyOwnWindowMap() {
        let items = [
            item(tag: .hiddenControlItem, windowID: 364, title: hiddenTitle),
        ]

        XCTAssertTrue(
            MenuBarItemManager.ghostControlItemWindowIDs(
                in: items,
                ownWindowIDsByTitle: [:]
            ).isEmpty
        )
    }

    /// Ordinary items never match control item titles and are never dropped.
    func testGhostDetectionIgnoresOrdinaryItems() {
        let items = [
            item(tag: .hiddenControlItem, windowID: 21542, title: hiddenTitle),
            item(tag: .appItem(bundleID: "com.apple.controlcenter", title: "Battery"), windowID: 850, title: "Battery"),
            item(tag: .appItem(bundleID: "com.if.Amphetamine", title: "Amphetamine"), windowID: 744, title: "Amphetamine"),
        ]

        let ghosts = MenuBarItemManager.ghostControlItemWindowIDs(
            in: items,
            ownWindowIDsByTitle: [hiddenTitle: 21542]
        )

        XCTAssertTrue(ghosts.isEmpty)
    }
}
